# 학습 담당자 가이드 📚

GPU 서버에서 모델 학습 후 프로덕션까지의 전체 워크플로우입니다.

## 🎯 전체 워크플로우

```
GPU 서버 (192.168.0.40)
  └─ Cycle 디렉토리에 체크포인트 저장
       ↓ (30분마다 자동 체크)
M1 MacBook Air
  └─ MD5 해시 변경 감지
       ↓
  TO-BE (8892) 자동 배포
       ↓
  Discord/Telegram 알림 📢
       ↓
  A/B 테스트 (수동)
       ↓
  성능 비교 (AS-IS vs TO-BE)
       ↓
  TO-BE 성능 좋음? → 승격 (promote.sh)
       ↓
  AS-IS (8891) 업데이트 ✅
```

**핵심**:
- ✅ **Cycle 디렉토리 저장** → TO-BE 자동 배포
- ✅ **A/B 테스트 후** → 수동 승격
- ✅ **AS-IS는 검증된 모델만** (자동 업데이트 안 됨)

## 📂 체크포인트 저장 위치

자동 배포 시스템은 다음 경로에서 **최신 체크포인트**를 찾아 **TO-BE 서버(8892)**로 배포합니다:

### 권장: Cycle 디렉토리 ⭐

```bash
~/mycnn/checkpoints_cycle8/best_model_cycle8.pth
~/mycnn/checkpoints_cycle8/best_model.pth
~/mycnn/checkpoints_cycle8/LiteCNNPro_best.pth
```

**특징**:
- Cycle별로 관리
- 여러 명명 방식 지원
- 타임스탬프 기준 최신 파일 자동 선택
- **TO-BE (8892)로 자동 배포** → 테스트 후 수동 승격

### 대안: Combined 디렉토리 (고급)

```bash
~/mycnn/checkpoints_combined/LiteCNNPro_best.pth
```

**특징**:
- 가장 높은 우선순위
- 직접 관리하는 경우에만 사용
- 파일명 고정

**⚠️ 중요**: Combined 디렉토리도 TO-BE로 배포됩니다. AS-IS (프로덕션)는 A/B 테스트 후 수동 승격으로만 업데이트됩니다.

## ✅ 올바른 저장 방법

### 권장: Cycle 디렉토리 ⭐

Cycle별로 관리하며, TO-BE 서버로 자동 배포됩니다:

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

### 대안: Combined 디렉토리 (고급)

직접 관리하는 경우:

```python
import torch

checkpoint = {
    'model_state_dict': model.state_dict(),
    'optimizer_state_dict': optimizer.state_dict(),
    'epoch': epoch,
    'loss': loss,
}

save_path = '/home/love-lee/mycnn/checkpoints_combined/LiteCNNPro_best.pth'
torch.save(checkpoint, save_path)
print(f"✅ 모델 저장 완료: {save_path}")
```

### 자동 베스트 모델 저장 (권장)

Validation 정확도 기준 자동 저장:

```python
class ModelCheckpoint:
    def __init__(self, cycle, filename='best_model.pth'):
        self.save_dir = f'/home/love-lee/mycnn/checkpoints_cycle{cycle}'
        self.filename = filename
        self.best_acc = 0.0
        os.makedirs(self.save_dir, exist_ok=True)
    
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
            print(f"   → TO-BE 서버로 자동 배포 대기 중 (최대 30분)")
            return True
        return False

# 사용법
checkpoint_saver = ModelCheckpoint(cycle=8)

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

## 🔍 배포 워크플로우

### 1. 체크포인트 저장 후

GPU 서버에서 확인:

```bash
# 파일 존재 확인
ls -lh ~/mycnn/checkpoints_cycle8/best_model_cycle8.pth

# MD5 해시 확인
md5sum ~/mycnn/checkpoints_cycle8/best_model_cycle8.pth
```

### 2. TO-BE 서버 자동 배포

- 자동 배포는 **30분마다** 실행됩니다
- 즉시 배포하려면 M1 MacBook에서:
  ```bash
  cd ~/projects/litecnn-pure-cpp
  ./scripts/deploy_from_gpu.sh
  ```

Discord/Telegram 알림:
```
🔥 새 모델 감지!

📊 모델 정보:
- Cycle: cycle 8
- 모델명: best_model_cycle8.pth
- 경로: ~/mycnn/checkpoints_cycle8/best_model_cycle8.pth
- 새 해시: b7c4e1f3...

✅ 배포 완료!
TO-BE 서버(8892)에 새 모델이 배포되었습니다.
```

### 3. A/B 테스트 (M1 MacBook)

```bash
# AS-IS (8891) vs TO-BE (8892) 성능 비교
./scripts/ab_test_v2.sh --notify
```

결과 확인:
```
=== 📊 A/B 테스트 결과 ===

AS-IS (8891): 정확도 85.00% (85/100)
TO-BE (8892): 정확도 87.00% (87/100)

🏆 승자: TO-BE
```

### 4. 프로덕션 승격 (수동)

**TO-BE 성능이 좋으면** AS-IS로 승격:

```bash
# 조건 확인 후 승격
./scripts/promote.sh

# 또는 강제 승격
./scripts/promote.sh --force
```

Discord/Telegram 알림:
```
✅ 모델 승격 완료

TO-BE(8892) → AS-IS(8891) 승격이 완료되었습니다.

📦 백업: model_8891_backup_20260206_092530.bin
```

### 5. 롤백 (문제 발생 시)

```bash
# 백업 목록 확인
./scripts/rollback.sh

# 특정 백업으로 롤백
./scripts/rollback.sh model_8891_backup_20260206_092530.bin
```

## 📊 권장 디렉토리 구조

```
~/mycnn/
├── checkpoints_cycle1/           # Cycle 1
│   └── best_model_cycle1.pth
├── checkpoints_cycle2/           # Cycle 2
│   └── best_model_cycle2.pth
├── checkpoints_cycle8/           # Cycle 8 (최신) ⭐
│   ├── best_model_cycle8.pth    # TO-BE 자동 배포 대상
│   ├── checkpoint_epoch50.pth   # 중간 체크포인트
│   └── checkpoint_epoch100.pth
├── checkpoints_combined/         # Combined (선택적)
│   └── LiteCNNPro_best.pth      # 직접 관리 시에만 사용
└── data/
    └── thudogs/
```

**배포 흐름**:
1. Cycle 디렉토리에 저장 → **TO-BE (8892) 자동 배포**
2. A/B 테스트 실행 → 성능 비교
3. 승격 (promote.sh) → **AS-IS (8891) 수동 업데이트**

## 🔧 자동 배포 플로우 요약

```python
# 1. 학습 중 베스트 모델 자동 저장 (Cycle 디렉토리)
checkpoint_saver = ModelCheckpoint(cycle=8)

for epoch in range(num_epochs):
    # ... 학습 ...
    val_acc = validate(model, val_loader)
    
    # 베스트 모델 자동 저장
    if checkpoint_saver.save_if_best(model, optimizer, epoch, val_acc, loss):
        print("✅ 새로운 베스트 모델 저장!")
        print("   → TO-BE 서버 자동 배포 대기 중 (최대 30분)")

# 2. TO-BE 배포 (자동, M1 MacBook에서)
#    - 30분마다 MD5 해시 체크
#    - 변경 감지 시 자동 배포
#    - Discord/Telegram 알림

# 3. A/B 테스트 (수동, M1 MacBook에서)
#    ./scripts/ab_test_v2.sh --notify

# 4. 승격 (수동, M1 MacBook에서, 성능 좋을 때만)
#    ./scripts/promote.sh

# 5. AS-IS 업데이트 완료!
```

**중요**: 
- **Cycle 디렉토리에 저장** → TO-BE 자동 배포
- **A/B 테스트 후** → 수동 승격 (promote.sh)
- **AS-IS는 자동 업데이트 안 됨** (안정성 보장)

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
