# AseLaps 2.1

Windows용 Aseprite 타임랩스 확장입니다. MP4/GIF 출력에는 Settings에서 FFmpeg를 지정하십시오.

## 설치

`AseLaps.aseprite-extension`을 Edit → Preferences → Extensions에서 설치하고 Aseprite를 다시 시작합니다. 패널 제목 `AseLaps 2.1.1`을 확인하십시오. 기존 녹화 데이터는 자동 삭제하거나 이동하지 않습니다.

## 녹화와 세션 파일

- 작업을 `.aseprite`로 저장한 뒤 New Recording…을 누릅니다. 기본 위치는 `%USERPROFILE%\Downloads\IncreParty_Illust\<작업명>__record`입니다. OneDrive 경로에는 녹화·편집·출력 파일을 쓰지 못하도록 차단합니다. 저장 창에서 위치와 이름을 바꿀 수 있습니다.
- 선택한 이름으로 세션 폴더를 만들고 `session.json`, `events.jsonl`, `frames.pack` 등을 보관합니다. 새 녹화는 무손실 RGBA 차분을 저장하는 v4입니다.
- Open Session…에서 `session.json`을 선택합니다. 마지막으로 연 폴더를 기억합니다. 이동·백업할 때는 세션 폴더 전체를 옮기십시오.
- 원본 작업 없이도 검토·편집·출력할 수 있습니다. Resume Selected는 현재 작업과 캔버스를 확인한 뒤 연결하여 재개합니다. 중지된 세션은 새 녹화를 시작하십시오.
- Pause/Stop은 활성 작업의 남은 변경을 저장합니다. Hide로 패널을 닫아도 녹화는 계속됩니다. 단순 프레임 이동과 동일 이미지의 중복 저장은 생략합니다.
- 기본 캡처 주기는 0.5초이며 Settings에서 1초·2초를 선택할 수 있습니다. 캔버스 크기가 바뀌어도 같은 세션에 기록합니다. Preview and Export에서 정렬이 필요한 경계를 검토할 수 있습니다.

## 프레임 제외와 편집

- Review Frames에서 원본 번호·파일명과 미리보기를 확인합니다. 제외할 번호를 `257, 300-350`처럼 입력하고 Exclude를 누릅니다. 비우면 현재 프레임을 처리합니다.
- Restore와 Undo Last Edit로 복원합니다. 원본 PNG는 삭제하지 않으며 편집 이력은 `edits.jsonl`에 보관합니다. 외부에서 삭제된 PNG도 이후 기록의 로드를 막지 않습니다.
- Edit Range…에서 검토 순서 기준 시작·끝 위치를 입력합니다. 프레임 수와 원시 이미지 메모리 예상치를 표시합니다. 필요한 범위만 여십시오.
- 새 Aseprite 애니메이션에서 삭제·수정·추가·순서 변경 후 Apply Edit to Session을 누르면 해당 구간을 교체합니다. 원본은 보존하고 Undo Last Edit로 되돌릴 수 있습니다.
- 편집 문서는 `.aseprite`로 저장 후 다시 열어 적용할 수 있습니다. 세션이 그 사이 바뀌었다면 구간을 다시 여십시오. 캔버스 크기는 유지해야 합니다.
- Export Edited Animation은 편집 문서만 출력합니다. 녹화 세션 편집은 먼저 Pause하십시오. 편집용 문서는 자동 녹화 대상에서 제외됩니다.

## 영상 저장

- Preview and Export → Export as…에서 MP4/GIF 파일명과 위치를 지정합니다. 파일 선택은 Aseprite의 기본 UI를 사용하므로 Browse용 CMD 창을 실행하지 않습니다.
- 초기 설정은 30 FPS, 5장마다 1장, 4배 확대, 흰 배경입니다. 이후 성공한 내보내기 설정과 출력 폴더를 기억합니다.
- Keep every N frames는 사용할 프레임 간격입니다. 1이면 전부, 10이면 10장마다 1장입니다. 제외·구간 편집 반영 후 간추리며 첫 장부터 지정된 간격으로 선택합니다.
- 출력 해상도·프레임 수·예상 길이를 표시합니다. 재생은 설정 FPS에 따른 균일한 간격이며 Aseprite 프레임별 duration은 사용하지 않습니다.
- PNG sequence는 지정한 이름의 새 폴더에 순번 PNG를 저장합니다. 기존 폴더와 충돌하면 다른 이름을 선택하십시오. Both 모드는 Full과 Clean의 길이를 각각 표시합니다.
- 누락된 프레임이 있으면 건너뛸지 확인합니다. 출력 중에는 Aseprite가 점유됩니다. PNG 저장·합성도 UI 스레드에서 수행되므로 큰 그림에서는 지연될 수 있습니다.

## 기존 세션

Open Legacy Folder에서 이전 저장소에 접근할 수 있습니다. v1 PNG와 v2 RGBA 세션은 그대로 열고 출력하며, v1의 Full/Clean도 유지합니다. v3 PNG도 그대로 열 수 있습니다.

Review Frames → Convert to PNG Copy…는 기존 세션을 새 PNG 세션으로 복사하고 픽셀 일치를 검증합니다. 원본 파일은 자동 삭제하지 않습니다. 변환 도중 실패하면 생성된 복사본은 완성되지 않았을 수 있으므로 원본을 유지하십시오.

## 빌드와 집중 검증

```powershell
.\build.ps1
.\tests\run.ps1 -Aseprite 'C:\Path\To\Aseprite.exe' -FFmpeg 'C:\Path\To\ffmpeg.exe'
```

probe, sampled, v2, v4 검증을 실행합니다. v2는 제외·복원, 구간 교체, 편집 문서 재열기, 오래된 편집 차단, 누락 프레임, 세션 이동, RGBA→PNG 복사와 지정 파일명 출력을 확인합니다.
