# AseLaps 2.2.0-rc.1

Windows용 Aseprite 타임랩스 확장 / Timelapse recording for Aseprite on Windows.

이 패키지는 출시 후보입니다. 검증 범위와 남은 제한은 저장소의 TEST_RESULTS.md에 기록합니다. 대상 환경은 Windows, Aseprite 1.3.18.6 이상입니다. 이전 Aseprite 버전의 호환성은 보증하지 않습니다.

This is a release candidate. See TEST_RESULTS.md in the repository for completed checks and remaining limitations. Target: Windows and Aseprite 1.3.18.6 or newer. Older versions are not supported.

## 빠른 시작

1. Edit → Preferences → Extensions에서 `AseLaps.aseprite-extension`을 설치하고 Aseprite를 다시 시작합니다.
2. File → AseLaps를 엽니다. 패널 버전이 `2.2.0-rc.1`인지 확인합니다.
3. 작업을 저장하고 New Recording…에서 녹화 위치와 이름을 선택합니다. 선택한 이름의 **세션 폴더**가 만들어집니다. 원본 작업 파일에 녹화를 저장하지 않습니다.
4. 그리면 기본 0.5초 간격으로 변경 사항을 기록합니다. Pause는 일시정지, Resume은 재개, Stop은 세션 종료입니다. Hide로 패널을 닫아도 녹화는 계속됩니다.
5. Preview and Export…를 열면 대상 녹화가 일시정지됩니다. Play·슬라이더로 확인하고 Output settings에서 MP4/GIF/PNG sequence를 선택합니다.
6. Export as…로 저장합니다. 준비와 출력 진행률을 확인하거나 Cancel로 취소할 수 있습니다. 녹화를 계속하려면 Resume을 누릅니다.

신규 설치 기본 위치는 `%USERPROFILE%\Downloads\AseLaps`입니다. Settings의 Recording folder에서 바꿀 수 있습니다. 기존 사용자의 저장 위치와 세션 연결은 보존하며 기존 폴더를 이동하지 않습니다. OneDrive 쓰기는 차단됩니다. 로컬 폴더를 선택하십시오.

## Quick start

1. Install `AseLaps.aseprite-extension` in Edit → Preferences → Extensions, then restart Aseprite.
2. Open File → AseLaps and check the panel version: `2.2.0-rc.1`.
3. Save your artwork, then choose New Recording… and a location/name. A **session folder** is created using that name; recording data is separate from your artwork.
4. Draw normally. Changes are sampled every 0.5 seconds by default. Pause allows Resume; Stop finishes the session. Hide keeps recording.
5. Open Preview and Export… to pause the selected recording. Use Play or the slider, then choose MP4, GIF or PNG sequence in Output settings.
6. Choose Export as…. Preparation and output show progress and support cancellation. Use Resume to continue recording afterwards.

New installations use `%USERPROFILE%\Downloads\AseLaps`. Change Recording folder in Settings. Existing paths and bindings are preserved, and old folders are never moved automatically. Choose a local folder outside OneDrive.

## FFmpeg

MP4/GIF에는 별도 FFmpeg가 필요합니다. [FFmpeg 다운로드 안내](https://ffmpeg.org/download.html)에서 Windows 빌드를 받아 압축을 풀고, Settings에서 `bin\ffmpeg.exe`를 선택한 뒤 Check FFmpeg를 누릅니다. FFmpeg는 패키지에 포함하지 않습니다. PNG sequence는 FFmpeg 없이 사용할 수 있습니다.

MP4/GIF require a separate FFmpeg installation. Follow the [FFmpeg download page](https://ffmpeg.org/download.html), extract a Windows build, select `bin\ffmpeg.exe` in Settings, and choose Check FFmpeg. FFmpeg is not bundled. PNG sequence works without it.

## 세션·편집 / Sessions and editing

- Open Session…에서 `session.json`을 선택합니다. 이동·백업 시 세션 폴더 **전체**를 보관하십시오. / Open `session.json`; move or back up the **entire folder**.
- 자동 연결은 원본 전체 경로가 일치할 때만 허용합니다. Resume Selected로 다른 저장된 작업에 명시적으로 연결할 수 있습니다. 같은 세션에 두 문서가 동시에 녹화할 수 없습니다. / Automatic attachment requires the full source path to match. Resume Selected explicitly links another saved artwork; simultaneous writers are blocked.
- Frame History…에서 제외·복원·Undo Last Edit를 사용합니다. 원본 캡처는 삭제하지 않습니다. Edit Range…는 편집용 애니메이션을 열며, Advanced → Apply Edit to Session으로 적용합니다. / Exclude, Restore and Undo preserve original captures. Edit Range… opens an animation; use Advanced → Apply Edit to Session to apply it.
- 캔버스 크기 변경은 같은 세션에 기록됩니다. 전체 캔버스 녹화의 모호한 정렬은 미리보기에서 검토합니다. Fixed crop은 최초 좌표·크기를 유지하고 캔버스 밖을 투명하게 처리합니다. / Resizes stay in the session. Review uncertain alignment for full-canvas recordings. Fixed crop keeps its coordinates and dimensions, with transparent pixels outside the canvas.
- v1~v4 세션을 읽습니다. Convert to PNG Copy…는 새 복사본을 만들고 픽셀을 검증합니다. 원본을 자동 변환하거나 삭제하지 않습니다. / v1–v4 sessions remain readable. Convert to PNG Copy… creates and verifies a separate copy.
- 중단된 편집 저널의 마지막 줄은 다음 편집 시 백업 후 복구합니다. 중간 손상은 오류로 보고하며 자동으로 건너뛰지 않습니다. / A truncated final edit is backed up and recovered on the next edit. Corruption in committed records is reported, not silently skipped.

## 출력과 제한 / Output and limitations

- 기본 출력: 30 FPS, 5장마다 1장, 4배 확대, 흰 배경. 첫 장부터 지정 간격으로 선택하며 프레임별 duration은 사용하지 않습니다. / Defaults: 30 FPS, every fifth capture, 4× scale, white background. Playback uses uniform frame timing.
- MP4는 투명 배경을 지원하지 않습니다. PNG sequence는 새 폴더로 저장합니다. 기존 영상은 새 영상이 완성된 뒤에만 교체합니다. / MP4 requires an opaque background. PNG sequences use a new folder. Existing videos are replaced only after successful encoding.
- 영상 준비 중 출력 위치에 임시 RGBA 파일을 사용합니다. 필요한 여유 공간은 대략 `캔버스 너비 × 높이 × 4 × 출력 프레임 수`입니다. 완료·취소 시 제거하며 실패 로그는 남깁니다. / Video preparation uses temporary RGBA storage beside the output, approximately `canvas width × height × 4 × output frame count` bytes. Temporary frames are removed on completion/cancellation; failure logs are retained.
- 작업은 나누어 실행하지만 단일 큰 이미지의 읽기·합성 중에는 지연될 수 있습니다. 앱 강제 종료 시 임시 파일이 남을 수 있습니다. / Work is processed in small steps; reading/compositing one large image can still pause the UI. A forced application exit can leave temporary files.

## 빌드와 검증 / Build and checks

```powershell
.\build.ps1
.\tests\run.ps1 -Aseprite 'C:\Path\To\Aseprite.exe' -FFmpeg 'C:\Path\To\ffmpeg.exe'
```

테스트는 격리된 설정과 `.test-work` 하위 폴더를 사용하며 stdout/stderr·종료 코드·시간 초과를 기록합니다. `-SourceRoot`로 압축 해제한 배포본의 상위 폴더를 지정할 수 있습니다(그 아래 `extension` 필요). / Tests use an isolated profile, log output/exit status/timeouts, and write artifacts under `.test-work`. Use `-SourceRoot` to test an extracted package under its `extension` subfolder.