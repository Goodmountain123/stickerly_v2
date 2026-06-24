# Stickerly Flutter

기존 Stickerly 웹 편집기를 Flutter로 이전하는 프로젝트입니다.

## 목표

- 기존 UI와 편집 흐름을 최대한 유지
- Android, iOS, Web, Desktop에서 일관된 프로젝트 편집 경험 제공
- 로컬 우선 저장과 Supabase 원격 자산 fallback 지원
- 원본 캔버스 해상도 PNG 출력 및 모바일 공유 지원

## 구조

```text
lib/
  app/                 앱 설정과 공통 디자인 시스템
  core/                저장소, 서비스, 공통 유틸리티
  features/            기능별 데이터·도메인·화면
```

기능 이전은 검증 가능한 작은 단계로 나누고 각 단계마다 별도 커밋합니다.
