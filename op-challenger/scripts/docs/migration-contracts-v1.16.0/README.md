# Migration v1.16.0 Documentation

이 폴더는 Optimism v1.16.0 마이그레이션과 관련된 문서를 포함합니다.

## 폴더 구조

```
migration-v1.16.0/
├── README.md                      # 이 파일
└── DeployImplementations-설명.md  # DeployImplementations.s.sol 상세 설명
```

## 주요 문서

### DeployImplementations-설명.md

`packages/contracts-bedrock/scripts/deploy/DeployImplementations.s.sol` 스크립트에 대한 종합적인 한국어 설명서입니다.

**포함 내용:**
- 스크립트의 역할과 목적
- 배포되는 모든 컨트랙트 카테고리별 설명
  - 코어 컨트랙트 (Core Contracts)
  - Fault Proof 시스템
  - RAT (Resource Accounting Token)
  - OPContractsManager 및 서브 컴포넌트
- 결정론적 배포 (CREATE2) 메커니즘
- Blueprint 시스템
- 입력/출력 파라미터 설명
- 배포 순서 및 의존성
- 사용 예시
- 보안 고려사항

## v1.16.0의 주요 변경사항

### 1. RAT (Resource Accounting Token) 추가
- 새로운 리소스 계정 시스템 도입
- `IRAT` 인터페이스 및 구현체 추가

### 2. MIPS64 지원
- MIPS32에서 MIPS64로 업그레이드
- Mainnet과 Sepolia에서는 MIPS64만 배포 강제

### 3. ETHLockbox
- 인터롭(Interoperability) 마이그레이션을 위한 새로운 컴포넌트
- ETH를 안전하게 잠그고 해제하는 메커니즘

### 4. OPContractsManager 아키텍처 개선
- 더 모듈화된 서브 컴포넌트 구조
- `OPContractsManagerInteropMigrator` 추가
- `OPContractsManagerStandardValidator` 개선

### 5. Super Dispute Games
- `SuperPermissionedDisputeGame`
- `SuperFaultDisputeGame` (Super Permissionless)
- 향상된 분쟁 해결 메커니즘

## 배포 프로세스

v1.16.0 마이그레이션의 일반적인 배포 순서:

```
1. DeploySuperchain.s.sol
   └─> Superchain 레벨 프록시 배포
       (SuperchainConfig, ProtocolVersions 등)

2. DeployImplementations.s.sol  ← 이 문서의 주제
   └─> 모든 구현체 컨트랙트 배포
       └─> OPContractsManager 배포

3. DeployOPChain.s.sol
   └─> 개별 OP Chain 프록시 배포
       └─> 구현체와 연결

4. 설정 및 검증
   └─> DisputeGame 타입 추가
   └─> 권한 설정
   └─> 통합 테스트
```

## 대상 독자

- **개발자**: OP Stack 배포 프로세스를 이해하고자 하는 개발자
- **운영자**: OP Chain 운영 및 유지보수 담당자
- **감사자**: 스마트 컨트랙트 보안 감사를 수행하는 감사자
- **기여자**: Optimism 생태계에 기여하고자 하는 개발자

## 추가 리소스

### 공식 문서
- [Optimism Docs](https://docs.optimism.io/)
- [OP Stack Specifications](https://specs.optimism.io/)
- [Superchain Explainer](https://docs.optimism.io/stack/explainer)

### 관련 코드
- `packages/contracts-bedrock/scripts/deploy/` - 배포 스크립트
- `packages/contracts-bedrock/src/` - 컨트랙트 소스 코드
- `packages/contracts-bedrock/test/` - 테스트 코드

### 보안 감사
- `docs/security-reviews/` - 보안 감사 리포트

## 기여하기

이 문서에 오류나 개선사항이 있다면:

1. 이슈 생성
2. Pull Request 제출
3. 커뮤니티 디스커션 참여

## 라이선스

이 문서는 Optimism 프로젝트의 라이선스를 따릅니다 (MIT License).

## 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|-----------|
| 2025-11-04 | 1.0.0 | 초기 문서 생성 |

---

**참고**: 이 문서는 v1.16.0 기준으로 작성되었으며, 향후 버전에서는 내용이 변경될 수 있습니다.

