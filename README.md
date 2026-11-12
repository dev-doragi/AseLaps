# AseLaps

Windows용 Aseprite 타임랩스 확장입니다. v1.2.0부터 편집 결과를 일정 간격으로 기록합니다.

## 설치와 업데이트

- `AseLaps.aseprite-extension`을 Edit → Preferences → Extensions에서 설치합니다.
- 업데이트 전 기존 AseLaps 패널에서 Stop을 누르십시오. 기존 세션은 그대로 보관됩니다.
- 확장을 다시 불러온 뒤 Start를 누르면 새 방식의 세션으로 이어서 기록합니다. 기존 세션과 새 세션은 각각 Browse Sessions에서 출력할 수 있으며 자동 병합하지 않습니다.
- 패널 제목의 `AseLaps 1.2.1`으로 적용 여부를 확인할 수 있습니다. MP4/GIF 출력에는 Settings에서 ffmpeg.exe를 지정하십시오.

## 녹화

- Start는 초기 상태를 기록합니다. Settings의 Initial snapshot을 끄면 첫 편집부터 기록합니다.
- 기본 기록 간격은 0.5초입니다. Settings에서 1초 또는 2초로 변경할 수 있으며 새 세션부터 적용됩니다.
- 간격 안의 여러 편집은 합칩니다. 샘플 시점의 활성 문서·프레임만 기록하며 단순 프레임 선택은 기록하지 않습니다.
- Pause/Stop은 활성 문서의 남은 변경을 기록합니다. Snapshot은 현재 상태를 즉시 기록합니다. 같은 프레임의 동일 이미지는 중복 저장하지 않습니다.
- 패널의 Hide 또는 X를 눌러도 녹화는 계속됩니다. File → AseLaps로 다시 엽니다.
- 비활성 문서는 다시 활성화될 때 기록됩니다. 문서를 닫기 직전의 미기록 변경을 남기려면 먼저 Stop 또는 Snapshot을 누르십시오.
- 녹화 중인 저장 문서는 다시 열면 자동 재개됩니다. v1 세션에서 재개하면 기존 파일을 보존하고 새 v2 세션을 만듭니다.
- 캔버스 크기 변경과 다른 이름 저장은 세션을 분리합니다. Fixed crop은 새 세션부터 적용됩니다.

## 저장과 출력

데이터 위치는 `%APPDATA%\Aseprite\AseLaps`입니다. Open Folder로 확인할 수 있습니다.

- 새 세션은 무손실·무압축 RGBA로 기록하여 녹화 중 PNG 압축과 픽셀 해시를 수행하지 않습니다. 1024×1024 한 장은 약 4MiB이므로 디스크 사용량에 유의하십시오.
- 새 세션의 History는 시간순 샘플 목록입니다. Full 출력과 PNG 추출을 지원하며 Clean/분기 기능은 제공하지 않습니다. 기존 v1 PNG 세션의 Full/Clean 기능은 유지됩니다.
- 새 세션의 출력 Frame interval 기본값은 1, 기존 세션은 8입니다. 첫 장과 마지막 장은 항상 포함됩니다.
- PNG 시퀀스, MP4, GIF 출력을 지원합니다. v1.2.1부터 MP4/GIF는 기록된 RGBA를 FFmpeg에 직접 전달하여 중간 PNG를 만들지 않습니다. 기존 PNG 세션도 원본을 직접 읽습니다. PNG 시퀀스를 선택한 경우에만 PNG로 변환합니다. 출력 중에는 Aseprite가 점유됩니다.
- 레퍼런스·숨김 레이어는 제외됩니다. 이미지 합성과 파일 쓰기는 여전히 Aseprite UI 스레드에서 수행되므로 큰 캔버스나 느린 디스크에서는 지연이 남을 수 있습니다.

## 빌드와 검증

```powershell
.\build.ps1
.\tests\run.ps1 -Aseprite 'C:\Path\To\Aseprite.exe' -FFmpeg 'C:\Path\To\ffmpeg.exe'
```

현재 실행기는 API probe와 sampled 회귀 테스트를 실행합니다. integration.lua와 crash.lua는 이전 v1 녹화 동작의 역사적 테스트로 현재 실행기에서는 사용하지 않습니다. FFmpeg를 생략하면 이미지 저장·복구·PNG 출력만 검증합니다.
