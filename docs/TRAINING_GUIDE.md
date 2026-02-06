# 학습 담당자 가이드 📚

GPU 서버에서 모델 학습 후 자동 배포가 작동하도록 체크포인트를 저장하는 방법입니다.

## 🎯 자동 배포 작동 방식

```
GPU 서버 (192.168.0.40)
└─ 체크포인트 저장
     ↓ (30분마다 자동 체크)
M1 MacBook Air
└─ MD5 해시 변경 감지
     ↓
TO-BE (8892) 자동 배포
```

## 📂 체크포인트 저장 위치

자동 배포 시스템은 다음 경로에서 **최신 체크포인트**를 찾습니다:

### 우선순위 1: Combined 디렉토리 (권장)

```bash
~/mycnn/checkpoints_combined/LiteCNNPro_best.pth
```

**특징**:
- 가장 높은 우선순위
- 프로덕션 준비된 모델 저장용
- 파일명 고정

### 우선순위 2: Cycle 디렉토리

```bash
~/mycnn/checkpoints_cycle8/best_model_cycle8.pth
~/mycnn/checkpoints_cycle8/best_model.pth
~/mycnn/checkpoints_cycle8/LiteCNNPro_best.pth
```

**특징**:
- Cycle별로 관리
- 여러 명명 방식 지원
- 타임스탬프 기준 최신 파일 자동 선택

## ✅ 올바른 저장 방법

### 방법 1: Combined 디렉토리 (권장)

학습 완료 후 최종 모델을 저장:

```python
import torch

# 모델 학습 완료 후
checkpoint = {
    'model_state_dict': model.state_dict(),
    'optimizer_state_dict': optimizer.state_dict(),
    'epoch': epoch,
    'loss': loss,
    # 기타 메타데이터
}

# 저장 경로
save_path = '/home/love-lee/mycnn/checkpoints_combined/LiteCNNPro_best.pth'

# 저장
torch.save(checkpoint, save_path)
print(f"✅ 모델 저장 완료: {save_path}")
```

### 방법 2: Cycle 디렉토리

Cycle별로 관리:

```python
import os

# Cycle 번호
cycle = 8

# 디렉토리 생성
checkpoint_dir = f'/home/love-lee/mycnn/checkpoints_cycle{cycle}'
os.makedirs(checkpoint_dir, exist_ok=True)

# 저장 경로
save_path = f'{checkpoint_dir}/best_model_cycle{cycle}.pth'

# 저장
torch.save(checkpoint, save_path)
print(f"✅ 모델 저장 완료: {save_path}")
```

### 방법 3: 자동 베스트 모델 저장

Validation 정확도 기준 자동 저장:

```python
class ModelCheckpoint:
    def __init__(self, save_dir, filename='LiteCNNPro_best.pth'):
        self.save_dir = save_dir
        self.filename = filename
        self.best_acc = 0.0
        os.makedirs(save_dir, exist_ok=True)
    
    def save_if_best(self, model, optimizer, epoch, acc, loss):
        if acc > self.best_acc:
            self.best_acc = acc
            
            checkpoint = {
                'model_state_dict': model.state_dict(),
                'optimizer_state_dict': optimizer.state_dict(),
                'epoch': epoch,
                'accuracy': acc,
                'loss': loss,
            }
            
            save_path = os.path.join(self.save_dir, self.filename)
            torch.save(checkpoint, save_path)
            
            print(f"✅ 새로운 베스트 모델 저장! (Acc: {acc:.2f}%)")
            print(f"   경로: {save_path}")
            return True
        return False

# 사용법
checkpoint_saver = ModelCheckpoint(
    save_dir='/home/love-lee/mycnn/checkpoints_combined'
)

# 매 에포크마다
for epoch in range(num_epochs):
    # ... 학습 ...
    val_acc = validate(model, val_loader)
    
    # 베스트 모델 자동 저장
    checkpoint_saver.save_if_best(model, optimizer, epoch, val_acc, loss)
```

## 🚫 피해야 할 사항

### ❌ 잘못된 경로

```python
# 자동 배포가 찾지 못하는 경로들
'/home/love-lee/mycnn/models/my_model.pth'  # ❌
'/home/love-lee/Desktop/checkpoint.pth'     # ❌
'/tmp/model.pth'                             # ❌
```

### ❌ 잘못된 파일명

```python
# 인식하지 못하는 파일명들
'my_model_final.pth'           # ❌
'model_v2.pth'                 # ❌
'checkpoint_epoch100.pth'      # ❌
```

**올바른 파일명**:
- `LiteCNNPro_best.pth` ✅
- `best_model.pth` ✅
- `best_model_cycle8.pth` ✅

## 📋 체크리스트

학습 완료 후 확인사항:

- [ ] 체크포인트가 올바른 경로에 저장되었는가?
  - `~/mycnn/checkpoints_combined/` 또는
  - `~/mycnn/checkpoints_cycleN/`
- [ ] 파일명이 올바른가?
  - `LiteCNNPro_best.pth` 또는
  - `best_model*.pth`
- [ ] 파일이 실제로 존재하는가?
  ```bash
  ls -lh ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth
  ```
- [ ] 파일 크기가 정상인가? (보통 4-12MB)
  ```bash
  du -h ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth
  ```

## 🔍 자동 배포 확인

### 1. 체크포인트 저장 후

GPU 서버에서 확인:

```bash
# 파일 존재 확인
ls -lh ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth

# MD5 해시 확인
md5sum ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth
```

### 2. 배포 대기

- 자동 배포는 **30분마다** 실행됩니다
- 즉시 배포하려면 M1 MacBook에서:
  ```bash
  cd ~/projects/litecnn-pure-cpp
  ./scripts/deploy_from_gpu.sh
  ```

### 3. 배포 확인

Discord 또는 Telegram에서 알림 확인:

```
🔥 새 모델 감지!

📊 모델 정보:
- Cycle: cycle 8
- 모델명: best_model_cycle8.pth
- 경로: ~/mycnn/checkpoints_cycle8/best_model_cycle8.pth
- 새 해시: b7c4e1f3...
```

## 📊 권장 디렉토리 구조

```
~/mycnn/
├── checkpoints_combined/         # 프로덕션 모델 (최우선)
│   └── LiteCNNPro_best.pth       # 자동 배포 대상
├── checkpoints_cycle1/           # Cycle 1
│   └── best_model_cycle1.pth
├── checkpoints_cycle2/           # Cycle 2
│   └── best_model_cycle2.pth
├── checkpoints_cycle8/           # Cycle 8 (최신)
│   ├── best_model_cycle8.pth
│   ├── checkpoint_epoch50.pth   # 중간 체크포인트
│   └── checkpoint_epoch100.pth
└── data/
    └── thudogs/
```

## 🔧 고급: 자동 복사 스크립트

학습 완료 후 자동으로 Combined 디렉토리에 복사:

```python
def copy_to_combined(checkpoint_path):
    """학습 완료 후 Combined 디렉토리에 복사"""
    import shutil
    
    combined_dir = '/home/love-lee/mycnn/checkpoints_combined'
    os.makedirs(combined_dir, exist_ok=True)
    
    target_path = os.path.join(combined_dir, 'LiteCNNPro_best.pth')
    
    # 복사
    shutil.copy2(checkpoint_path, target_path)
    print(f"✅ Combined 디렉토리에 복사 완료!")
    print(f"   {checkpoint_path}")
    print(f"   → {target_path}")
    print(f"   자동 배포 대기 중 (최대 30분)...")

# 사용법
# 학습 완료 후
final_checkpoint = f'~/mycnn/checkpoints_cycle8/best_model_cycle8.pth'
copy_to_combined(final_checkpoint)
```

## 🚨 문제 해결

### 자동 배포가 안 됨

1. **파일 경로 확인**:
   ```bash
   ls -lh ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth
   ```

2. **파일 권한 확인**:
   ```bash
   chmod 644 ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth
   ```

3. **MD5 해시 변경 확인**:
   ```bash
   md5sum ~/mycnn/checkpoints_combined/LiteCNNPro_best.pth
   ```

4. **수동 배포 시도**:
   ```bash
   # M1 MacBook에서
   cd ~/projects/litecnn-pure-cpp
   ./scripts/deploy_from_gpu.sh
   ```

### 파일이 너무 큼

PyTorch 체크포인트에서 불필요한 데이터 제거:

```python
# 경량화된 저장 (모델 가중치만)
torch.save({
    'model_state_dict': model.state_dict(),
}, save_path)

# 전체 저장 (옵티마이저 등 포함)
torch.save({
    'model_state_dict': model.state_dict(),
    'optimizer_state_dict': optimizer.state_dict(),
    'epoch': epoch,
    'loss': loss,
}, save_path)
```

## 📞 연락처

문제 발생 시:
- Discord #server-monitoring 채널
- 또는 텔리크로에게 직접 문의

---

**작성**: 텔리크로 🖤  
**마지막 업데이트**: 2026-02-06  
**자동 배포 주기**: 30분
