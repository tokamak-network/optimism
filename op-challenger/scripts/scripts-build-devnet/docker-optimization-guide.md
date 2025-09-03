# Docker Desktop 최적화 가이드

## Kurtosis 연결 문제 해결을 위한 Docker 설정

### 1. Docker Desktop 리소스 설정
- **메모리**: 최소 8GB, 권장 12GB+
- **CPU**: 4코어 이상
- **디스크**: 50GB 이상

### 2. 고급 설정
```bash
# Docker Desktop > Settings > Docker Engine에서 설정 추가:
{
  "builder": {
    "gc": {
      "enabled": true,
      "policy": [
        {
          "keepStorage": "20GB",
          "filter": [
            "unused-for=2160h"
          ]
        }
      ]
    }
  },
  "experimental": false,
  "features": {
    "buildkit": true
  },
  "max-concurrent-downloads": 3,
  "max-concurrent-uploads": 3
}
```

### 3. 네트워크 최적화
- Docker Desktop > Settings > Resources > Network에서:
  - **Enable VirtioFS**: 체크
  - **Use Rosetta for x86/amd64 emulation**: 체크 해제

### 4. 실행 전 체크리스트
1. Docker Desktop 완전 재시작
2. 불필요한 컨테이너/이미지 정리: `docker system prune -a`
3. 메모리 충분한지 확인: Activity Monitor에서 Memory Pressure가 녹색인지 확인
4. 다른 개발 서버들 임시 중단 (포트 충돌 방지)