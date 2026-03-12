# ============================================================
# SteerX Dockerfile — CUDA 12.1 + Python 3.10 + PyTorch 2.4.1
# ============================================================
# 빌드:   docker build -t steerx:latest .
#
# 실행 (소스 마운트 — 개발/테스트용, 호스트 코드 변경 즉시 반영):
#   docker run --gpus all -it --name steerx \
#     -v $(pwd):/workspace/SteerX \
#     --shm-size=16g \
#     steerx:latest bash
#
# 실행 (이미지 내장 코드 — 배포용):
#   docker run --gpus all -it --name steerx \
#     -v $(pwd)/steerx_ckpt:/workspace/SteerX/steerx_ckpt \
#     --shm-size=16g \
#     steerx:latest bash
#
# 체크포인트(19GB)는 빌드에 포함하지 않고 볼륨 마운트로 사용.
# 최초 1회: gdown --folder https://drive.google.com/drive/folders/1YrsZq54YMXKtNLwxqOC7yAx_nYlyymPo
# ============================================================

FROM nvidia/cuda:12.1.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# ── 시스템 패키지 ─────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 python3.10-dev python3.10-venv python3-pip \
        git wget curl ffmpeg \
        libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
        build-essential gcc g++ ninja-build \
    && rm -rf /var/lib/apt/lists/*

# python3 → python3.10
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.10 1

# ── 작업 디렉토리 및 venv ────────────────────────────────────
WORKDIR /workspace
RUN python3.10 -m venv /workspace/venv
ENV VIRTUAL_ENV=/workspace/venv
ENV PATH="/workspace/venv/bin:$PATH"

# pip 업그레이드
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# ── 1단계: PyTorch + pytorch3d (캐시 레이어) ─────────────────
RUN pip install --no-cache-dir \
        torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1 \
        --index-url https://download.pytorch.org/whl/cu121

RUN pip install --no-cache-dir \
        --extra-index-url https://miropsota.github.io/torch_packages_builder \
        pytorch3d==0.7.8+pt2.4.1cu121

# ── 2단계: requirements.txt만 먼저 복사 (캐시 최적화) ────────
COPY requirements.txt /workspace/SteerX/requirements.txt

# 일반 pip requirements (git+, -e 패키지 제외)
RUN grep -v '^git+' /workspace/SteerX/requirements.txt | \
    grep -v '^-e' | \
    pip install --no-cache-dir -r /dev/stdin

# ── 3단계: CUDA 빌드가 필요한 패키지들 ──────────────────────
ENV CUDA_HOME=/usr/local/cuda
ENV TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6;8.9;9.0"

# diff-gaussian-rasterization
RUN pip install --no-cache-dir --no-build-isolation \
        git+https://github.com/byeongjun-park/diff-gaussian-rasterization

# FeatUp
RUN pip install --no-cache-dir --no-build-isolation \
        git+https://github.com/mhamilton723/FeatUp

# ── 4단계: 소스 코드 전체 복사 (의존성 빌드 후 ← 캐시 최적화) ──
COPY . /workspace/SteerX/
# 체크포인트 디렉토리 생성 (마운트 포인트)
RUN mkdir -p /workspace/SteerX/steerx_ckpt

# ── 5단계: editable 패키지 (-e) ──────────────────────────────
# SAM2
RUN pip install --no-cache-dir -e /workspace/SteerX/steerx_diffusers/geometry_steering/monst3r/third_party/sam2

# viser
RUN pip install --no-cache-dir -e /workspace/SteerX/viser

# ── 6단계: CuRoPE 커널 빌드 (선택적, 빠른 성능) ─────────────
RUN cd /workspace/SteerX/steerx_diffusers/geometry_steering/croco/models/curope/ && \
    python setup.py build_ext --inplace && \
    cd /workspace/SteerX

# ── 환경 변수 ────────────────────────────────────────────────
ENV PYTHONPATH=/workspace/SteerX
WORKDIR /workspace/SteerX

CMD ["bash"]
