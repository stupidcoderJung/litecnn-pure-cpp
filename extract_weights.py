#!/usr/bin/env python3
"""
PyTorch 체크포인트에서 가중치를 추출하여 binary 형식으로 저장
"""
import torch
import numpy as np
import struct
import sys
from pathlib import Path

def extract_weights(checkpoint_path, output_path):
    """체크포인트에서 가중치 추출"""
    print(f"Loading checkpoint: {checkpoint_path}")
    checkpoint = torch.load(checkpoint_path, map_location='cpu')
    
    # state_dict 추출
    if 'model_state_dict' in checkpoint:
        state_dict = checkpoint['model_state_dict']
    elif 'state_dict' in checkpoint:
        state_dict = checkpoint['state_dict']
    else:
        state_dict = checkpoint
    
    print(f"Found {len(state_dict)} parameters")
    
    # Binary 파일로 저장
    with open(output_path, 'wb') as f:
        # 매직 넘버와 버전 정보
        f.write(b'LCNN')  # Magic number
        f.write(struct.pack('I', 1))  # Version
        
        # 파라미터 개수
        f.write(struct.pack('I', len(state_dict)))
        
        for name, param in state_dict.items():
            print(f"  {name}: {param.shape}")
            
            # 파라미터 이름 (최대 256 bytes)
            name_bytes = name.encode('utf-8')[:256]
            f.write(struct.pack('I', len(name_bytes)))
            f.write(name_bytes)
            
            # 텐서 데이터
            data = param.cpu().numpy().astype(np.float32)
            
            # Shape 정보
            ndim = len(data.shape)
            f.write(struct.pack('I', ndim))
            for dim in data.shape:
                f.write(struct.pack('I', dim))
            
            # 데이터 (C-contiguous order)
            data_flat = data.flatten('C')
            f.write(struct.pack(f'{len(data_flat)}f', *data_flat))
    
    print(f"\nWeights saved to: {output_path}")
    print(f"File size: {Path(output_path).stat().st_size / 1024 / 1024:.2f} MB")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python extract_weights.py <checkpoint_path> [output_path]")
        print("Example: python extract_weights.py model.pth weights/model_weights.bin")
        sys.exit(1)
    
    checkpoint_path = Path(sys.argv[1]).expanduser()
    output_path = sys.argv[2] if len(sys.argv) > 2 else './model_weights.bin'
    
    extract_weights(checkpoint_path, output_path)
