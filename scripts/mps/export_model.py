#!/usr/bin/env python3
"""
Cycle 13 MPS-optimized TorchScript Exporter
Target: <10ms inference on M1 MacBook Air
"""

import torch
import torch.nn as nn
import time
from pathlib import Path

# ===========================
# Model Definition (from GPU server)
# ===========================
class SEBlock(nn.Module):
    """채널별 중요도 학습 - 정확도 2-3% 향상"""
    def __init__(self, channels, reduction=4):
        super().__init__()
        self.squeeze = nn.AdaptiveAvgPool2d(1)
        self.excitation = nn.Sequential(
            nn.Linear(channels, channels // reduction, bias=False),
            nn.ReLU(),
            nn.Linear(channels // reduction, channels, bias=False),
            nn.Sigmoid()
        )
    
    def forward(self, x):
        b, c, _, _ = x.size()
        y = self.squeeze(x).view(b, c)
        y = self.excitation(y).view(b, c, 1, 1)
        return x * y.expand_as(x)


class DepthwiseSeparableConv(nn.Module):
    def __init__(self, in_ch, out_ch, stride=1, use_se=True):
        super().__init__()
        self.depthwise = nn.Conv2d(
            in_ch, in_ch, 3, stride=stride, padding=1, groups=in_ch, bias=False
        )
        self.bn1 = nn.BatchNorm2d(in_ch)
        
        self.pointwise = nn.Conv2d(in_ch, out_ch, 1, bias=False)
        self.bn2 = nn.BatchNorm2d(out_ch)
        
        self.relu = nn.ReLU6()  # ReLU6이 모바일에서 더 안정적
        self.se = SEBlock(out_ch) if use_se else nn.Identity()
    
    def forward(self, x):
        x = self.relu(self.bn1(self.depthwise(x)))
        x = self.relu(self.bn2(self.pointwise(x)))
        x = self.se(x)
        return x


class LiteCNNPro(nn.Module):
    """
    강화된 LiteCNN - 약 600K 파라미터
    목표: Stanford Dogs 70% 정확도
    """
    def __init__(self, num_classes=131, dropout=0.5):
        super().__init__()
        
        # Stem - 첫 레이어
        self.stem = nn.Sequential(
            nn.Conv2d(3, 32, 3, stride=2, padding=1, bias=False),  # 224→112
            nn.BatchNorm2d(32),
            nn.ReLU6(),
        )
        
        # Feature extractor
        self.features = nn.Sequential(
            # Stage 1: 112 → 56
            DepthwiseSeparableConv(32, 64, stride=2),
            
            # Stage 2: 56 → 28
            DepthwiseSeparableConv(64, 128, stride=1),
            DepthwiseSeparableConv(128, 128, stride=2),
            
            # Stage 3: 28 → 14
            DepthwiseSeparableConv(128, 256, stride=1),
            DepthwiseSeparableConv(256, 256, stride=2),
            
            # Stage 4: 14 → 7
            DepthwiseSeparableConv(256, 512, stride=1),
            DepthwiseSeparableConv(512, 512, stride=2),
        )
        
        self.avgpool = nn.AdaptiveAvgPool2d((1, 1))
        
        self.classifier = nn.Sequential(
            nn.Flatten(),
            nn.Dropout(dropout),
            nn.Linear(512, 256),
            nn.ReLU6(),
            nn.Dropout(dropout * 0.6),
            nn.Linear(256, num_classes)
        )
        
        # 가중치 초기화
        self._initialize_weights()
    
    def _initialize_weights(self):
        for m in self.modules():
            if isinstance(m, nn.Conv2d):
                nn.init.kaiming_normal_(m.weight, mode='fan_out', nonlinearity='relu')
            elif isinstance(m, nn.BatchNorm2d):
                nn.init.ones_(m.weight)
                nn.init.zeros_(m.bias)
            elif isinstance(m, nn.Linear):
                nn.init.normal_(m.weight, 0, 0.01)
                if m.bias is not None:
                    nn.init.zeros_(m.bias)
    
    def forward(self, x):
        x = self.stem(x)
        x = self.features(x)
        x = self.avgpool(x)
        x = self.classifier(x)
        return x

# ===========================
# Main Conversion
# ===========================
def main():
    print("=" * 60)
    print("Cycle 13 MPS TorchScript Converter")
    print("=" * 60)
    
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print(f"Using device: {device}")
    
    # Load checkpoint
    checkpoint_path = "weights/cycle13_best.pth"
    print(f"\n📦 Loading checkpoint: {checkpoint_path}")
    checkpoint = torch.load(checkpoint_path, map_location=device, weights_only=False)
    
    val_acc = checkpoint['val_acc']
    epoch = checkpoint['epoch']
    print(f"   Epoch: {epoch}, Val Acc: {val_acc:.2f}%")
    
    # Create model (130 classes!)
    print("\n🏗️  Creating LiteCNNPro model (130 classes)...")
    model = LiteCNNPro(num_classes=130, dropout=0.5)
    model.load_state_dict(checkpoint['model_state_dict'])
    model.to(device)
    model.eval()
    
    total_params = sum(p.numel() for p in model.parameters())
    print(f"   Parameters: {total_params:,}")
    
    # Warmup (MPS optimization)
    print("\n🔥 Warming up MPS...")
    dummy_input = torch.randn(1, 3, 224, 224, device=device)
    with torch.no_grad():
        for _ in range(10):
            _ = model(dummy_input)
    
    # Benchmark
    print("\n⏱️  Benchmarking (50 runs)...")
    times = []
    with torch.no_grad():
        for i in range(50):
            start = time.perf_counter()
            _ = model(dummy_input)
            if device.type == 'mps':
                torch.mps.synchronize()
            elapsed = (time.perf_counter() - start) * 1000
            times.append(elapsed)
    
    avg_time = sum(times) / len(times)
    min_time = min(times)
    max_time = max(times)
    print(f"   Average: {avg_time:.2f}ms")
    print(f"   Min: {min_time:.2f}ms")
    print(f"   Max: {max_time:.2f}ms")
    
    # Export TorchScript
    print("\n📤 Exporting to TorchScript...")
    traced_model = torch.jit.trace(model, dummy_input)
    traced_model = torch.jit.optimize_for_inference(traced_model)
    
    output_path = "weights/cycle13_mps_traced.pt"
    torch.jit.save(traced_model, output_path)
    
    file_size = Path(output_path).stat().st_size / (1024 * 1024)
    print(f"   Saved: {output_path} ({file_size:.2f}MB)")
    
    # Verify
    print("\n✅ Verification...")
    loaded = torch.jit.load(output_path, map_location=device)
    loaded.eval()
    
    with torch.no_grad():
        original_output = model(dummy_input)
        loaded_output = loaded(dummy_input)
        max_diff = torch.max(torch.abs(original_output - loaded_output)).item()
    
    print(f"   Max difference: {max_diff:.2e}")
    if max_diff < 1e-5:
        print("   ✅ Verification passed!")
    else:
        print(f"   ⚠️  Large difference detected: {max_diff}")
    
    print("\n" + "=" * 60)
    print("✅ Conversion complete!")
    print(f"   Output: {output_path}")
    print(f"   Inference time: {avg_time:.2f}ms (target: <10ms)")
    print("=" * 60)

if __name__ == "__main__":
    main()
