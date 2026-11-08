# Oto — thông tin chủ dự án cần bổ sung

Ngày: 2026-11-08. Chủ dự án đã điền bảng Q và mẫu trả lời ở phần 8; phần tổng hợp sau đây phân biệt lựa chọn đã xác nhận, cách hiểu của agent và phần còn chờ. Các bảng B/E chưa điền không được tự coi là yêu cầu đã duyệt.

## Tổng hợp sau khi đọc câu trả lời

- Đã chốt: iOS/iPadOS 17+ có fallback; UI cơ bản trước, bổ sung ảnh sau; lyrics theo dòng, Anh/Việt, tham khảo Kaset; iPad cạnh nhau khi rộng và stack khi hẹp.
- Đã chốt: restore queue, vào Home; không tự phát nền. Cách triển khai mặc định là không tự khởi phát nhạc khi cold launch; quay lại foreground trong một phiên đang phát không được làm nhạc dừng. Home có thể là shell trước khi có feed thật.
- Bảng Q01 nêu thứ tự phát nền -> lời -> UI, phần 8 ghi không có ưu tiên thêm; Q02 nêu vertical slice, phần 8 giao agents chọn. Cách hiểu: agents được chọn thứ tự task, tiếp tục dùng bảng Q làm định hướng chất lượng chứ không tạo thêm feature ngoài plan.
- “Giống Kaset” là yêu cầu tham khảo hành vi thực tế, không xác nhận mọi tính năng đề xuất đã có trong Kaset. Khi port phải đọc code và ghi phần nào giữ nguyên, phần nào là bổ sung (chẳng hạn chọn nguồn/offset).
- Đã chốt: Gemini Google Login + Pro, không phát sinh phí; repo GitHub được chỉ định ở phần 8; commit/push mỗi task code sau checks và review, không bỏ qua; chú thích/báo cáo tiếng Việt đơn giản.
- Đã chốt qua trả lời tiếp theo: dừng lúc 05:00 sáng giờ Việt Nam (`Asia/Ho_Chi_Minh`), không phải chạy tối đa 5 tiếng; cả Gemini và Codex chỉ dùng hạn mức gói đăng nhập hiện có. Hết hạn mức thì dừng sớm; luôn để handoff người dùng đọc được. Mỗi phiên tự động ghi ngày cutoff cụ thể trước khi bắt đầu.
- Chưa trả lời, chưa chặn foundation: Developer membership, phụ kiện thử, số người chia sẻ, bài mẫu, ảnh tham khảo. Cần thu thập trước cài máy thật, xác nhận capability hoặc polish UI tương ứng.

Phần trả lời trực tiếp của chủ dự án dưới đây được giữ nguyên để đối chiếu. B/E chưa điền sẽ được agents đề xuất theo convention ở task liên quan; chỉ hỏi khi lựa chọn ảnh hưởng đáng kể đến sản phẩm.

## 1. Đã biết — không cần trả lời lại

| Thông tin | Đã xác nhận |
| --- | --- |
| Sản phẩm | Oto, app iPhone/iPad tập trung YouTube Music |
| Trải nghiệm | Player lấy cảm hứng Apple Music, lời nhạc đa nguồn |
| Người dùng đầu | Chủ dự án trước, có thể chia sẻ nhóm nhỏ sau |
| Thiết bị | iPad Gen 9, iPhone 13 Pro Max |
| OS người dùng cung cấp | iOS/iPadOS 27; cần ghi build thực tế khi thử |
| Tài khoản | Có YouTube Premium; không cần cung cấp danh tính tài khoản |
| Agent | Gemini CLI code chính, Codex review |
| Phân phối | Chưa làm App Store |

Min OS 17 có fallback đã được chủ dự án đồng ý. Swift 6/SwiftUI, LRCLIB/YTM, layout adaptive và phạm vi triển khai chi tiết theo PROJECT_PLAN; agents được chọn thứ tự task trong phạm vi đã ghi. Chưa có evidence phát nền hoặc xác nhận toàn bộ lựa chọn giao diện.

## 2. Những lựa chọn nên chốt trước khi làm phần tương ứng

Không cần đợi trả lời hết tài liệu mới dựng foundation. Q01–Q04 định hình phạm vi; Q05–Q10 cần trước khi hoàn thiện player/lyrics. Nếu lựa chọn xung đột với plan, cập nhật plan trước khi code.

| Mã | Bạn cần bổ sung | Xác nhận |
| --- | --- | --- |
| Q01 | Xếp hạng ba điều quan trọng nhất: phát nền, lời, giao diện, tìm kiếm/thư viện, pin | Phát nền ổn định -> lời khớp -> UI mượt |
| Q02 | Bản đầu phải có tính năng nào; tính năng nào có thể để sau? | Search, player, queue, lyrics; Home/Library sau vertical slice |
| Q03 | Hỗ trợ OS thấp nhất? Chấp nhận hiệu ứng đơn giản trên máy cũ? | iOS/iPadOS 17+, có fallback |
| Q04 | Nhóm người dùng sau này: khoảng bao nhiêu người, chủ yếu máy/OS nào, có Premium không? | Chưa chốt số lượng; xác minh capability theo tài khoản, không hứa guest/free phát nền |
| Q05 | Khi mở app: Home, Search hay bài đang nghe? Có tự phát không? | Restore queue, không tự phát nền, để ở màn hình Home |
| Q06 | Giao diện mong muốn: Apple Music ở điểm nào? Màu, spacing, lyrics, gestures hay bố cục? | Chú thích từng điểm qua ảnh/video, giữ nhận diện Oto. Tuy nhiên chưa design UI cho app, có thể dựng tạm 1 bộ UI cơ bản, và có thể bổ sung hình ảnh sau. |
| Q07 | Lyrics ưu tiên ngôn ngữ nào? Có cần karaoke từng chữ, dịch, romanization? | Theo dòng trước; chỉ từng chữ khi nguồn có timing thật; dịch/romanization sau. Lyrics trước đây đang ưu tiên ngôn ngữ tiếng anh, giờ có thêm ngôn ngữ việt nữa, Cách hoạt động Lyrics có thể giữ giống Kaset |
| Q08 | iPad: player + lyrics cạnh nhau hay player một màn hình, lyrics bật riêng? | Cạnh nhau khi rộng; stack khi hẹp. Có thể tham khảo cách Apple Music đang hoạt động. |
| Q09 | Khi lyric sai: tự chọn nguồn khác, người dùng chọn bản, chỉnh offset hay cả hai? | Hiện nguồn + chọn bản + offset theo track/version. Tạm thời có thể làm giống cách Kaset đang quy định |
| Q10 | Ba hành vi bạn không chấp nhận ở một app nhạc? | Dừng khi khóa máy, lời sai bản thu, next nhảy hai bài. |

## 3. Luồng nghe nhạc và nghiệp vụ chi tiết

Điền khi có sở thích cụ thể; agent có thể đề xuất lựa chọn theo convention trước khi làm. Những thao tác này phải có acceptance criteria, không suy từ ảnh tĩnh.

| Mã | Lựa chọn cần mô tả |
| --- | --- |
| B01 | Chạm một bài trong album/search: thay queue bằng danh sách hiện tại hay phát riêng? |
| B02 | Phân biệt Play next, Add to queue, Play album; cách xử lý cùng bài xuất hiện nhiều lần |
| B03 | Bấm Previous: về đầu bài sau bao nhiêu giây, hay luôn sang bài trước? |
| B04 | Hết queue: dừng hay tự gợi ý bài tiếp? Autoplay mặc định có bật không? |
| B05 | Shuffle/repeat: có lưu qua lần mở app? Shuffle có giữ bài đang nghe? |
| B06 | App bị đóng: nhớ bài/queue/vị trí đến mức nào? Khôi phục để người dùng bấm play hay tự tiếp tục? |
| B07 | Gặp bài không khả dụng: báo lỗi rồi dừng, hay bỏ qua có thông báo? Giới hạn bỏ qua liên tiếp? |
| B08 | Mất mạng/hết phiên: giữ queue, retry thủ công hay tự retry giới hạn? Không tự lặp màn hình login |
| B09 | Library bản đầu chỉ đọc hay cần like/unlike, tạo/sửa playlist? Mutation làm sau theo plan hiện tại |
| B10 | Một tài khoản trước hay nhiều tài khoản? Brand account có cần từ đầu không? |
| B11 | AirPlay, AirPods/Bluetooth, loa ngoài nào sẵn có để thử? CarPlay chưa thuộc MVP |
| B12 | Có cần chặn bài explicit, chọn vùng/nội dung/ngôn ngữ đề xuất? Phân biệt content language và ngôn ngữ UI |
| B13 | Cử chỉ mini player: tap mở, kéo đóng, vuốt đổi bài? Có cần nút tương đương cho accessibility? |
| B14 | Khi cuộn lyrics thủ công: bao lâu tự bám lại, hay có nút quay về dòng hiện tại? |

## 4. Ảnh, video và tài sản thiết kế

Chuẩn bị **3–6 ảnh và 1–2 video ngắn** là đủ cho vòng thiết kế đầu. Đây là gợi ý số lượng, không phải điều kiện bắt buộc. Xem cách đặt tên/chú thích tại [design/references/README.md](../design/references/README.md).

- Ảnh ưu tiên: iPhone Now Playing, lyrics, mini player; iPad player+lyrics và layout thư viện nếu quan tâm.
- Video: thao tác mini -> full player -> lyrics -> dismiss; cuộn lời, seek và đổi bài. Nói rõ thích chuyển động nào, thay vì yêu cầu agent tự suy từ mọi chi tiết.
- Một ảnh ví dụ không thích, kèm lý do, giúp loại bỏ những hướng thiết kế không phù hợp.
- Mỗi tài liệu tham khảo ghi nguồn/app/version nếu biết, điều muốn học, điều muốn thay đổi, và thiết bị/kích thước.
- Chưa có ảnh: mô tả bằng chữ vẫn đủ bắt đầu. Figma/wireframe là tùy chọn, không cần mua công cụ.
- Logo/app icon, accent color, tên hiển thị và font: có thì gửi nguồn hợp lệ; chưa có dùng placeholder và system font. Font bên ngoài cần quyền sử dụng và đánh giá kích thước app.
- Phân biệt tài liệu tham khảo với asset được phép nhúng vào app. Không tự copy ảnh bìa/logo/lyric từ screenshot thành tài sản đóng gói.
- Che thông tin tài khoản, notification, playlist riêng tư trước khi đưa ảnh vào repo. Không cần video chứa bước nhập mật khẩu.

## 5. Bộ ví dụ nhạc để nghiệm thu

Gửi **khoảng 10 link YouTube Music công khai** là hữu ích; không cần gửi audio tải về hoặc toàn bộ lời. Với mỗi link, ghi điều cần kiểm tra. Không thêm link playlist riêng tư hoặc thông tin người sở hữu.

| Nhóm ví dụ | Mục đích |
| --- | --- |
| Bài Việt thường nghe | Dấu tiếng Việt, title/artist, lời và duration |
| Anh / Hàn / Nhật hoặc ngôn ngữ bạn nghe | Unicode, wrapping, matching nhiều nghệ sĩ |
| Bản studio và live/remix của cùng bài | Không lấy nhầm lời hoặc timestamp của bản khác |
| Bài không lời / không tìm được lyrics | Trạng thái instrumental/unavailable |
| Tên dài, nhiều nghệ sĩ, album art rất sáng/tối | Layout, truncation và contrast |
| Bài ngắn, bài dài, album/playlist công khai | Auto-next, queue order, resume |

Mẫu mỗi ví dụ:

```text
URL công khai:
Tên bài / nghệ sĩ / bản thu:
Mình muốn kiểm tra:
Điểm sai từng gặp (nếu có):
Kỳ vọng:
```

Agent tạo fixture giả hoặc đã sanitize cho test; một link bài hát không chứng minh lyrics có sẵn hoặc phát được trên mọi tài khoản/vùng.

## 6. Môi trường và quyền vận hành

Bạn chỉ cần trả lời sở thích và trạng thái đăng nhập, agent tự kiểm kê phiên bản công cụ bằng lệnh an toàn khi đến bước setup. Không gửi auth file, API key hoặc signing key.

| Mã | Thông tin cần biết | Ai cung cấp |
| --- | --- | --- |
| E01 | Gemini CLI version/model; cách dùng Google login hay API/Vertex; có cho dùng dịch vụ phát sinh phí không? | Agent kiểm tra version/config không chứa secrets; bạn chốt ngân sách |
| E02 | Codex CLI version/model và cách xác thực; giới hạn chi phí mong muốn | Tương tự E01; không giả định gói web bao gồm mọi API usage |
| E03 | Số vòng sửa tối đa/task, thời lượng mỗi đợt, khi quota hết có chờ hay dừng? | Bạn chọn hoặc nhận đề xuất trong AGENT_WORKFLOW |
| E04 | Bạn có Apple Developer membership không? Chỉ cần có/không, không gửi Apple ID | Bạn cung cấp; signing được thiết lập riêng khi cần cài |
| E05 | Có thể kết nối hai máy để cài/chạy và tự đăng nhập trong app vào lúc nào? | Bạn cung cấp; mỗi đợt chạy tuân theo ủy quyền phiên |
| E06 | Có cho agent tự commit local sau review? Remote repo đã có chưa? | Chưa mặc định cho phép push/publish; cần xác định Git root Oto riêng |
| E07 | Bạn muốn xem báo cáo theo task, theo milestone hay theo phiên? | Đề xuất báo cáo mỗi task + checkpoint khi dừng |
| E08 | AirPods/thiết bị Bluetooth/AirPlay có sẵn để thử | Bạn cung cấp; thiếu phụ kiện ghi NOT TESTED |

Các hành động đã được ủy quyền trong phiên không cần xin lại. Việc cung cấp dữ liệu vào mẫu không tự cấp quyền đọc tài khoản, chạy trên thiết bị hoặc bắt đầu một vòng agent tự động.

## 7. Ai viết những tài liệu còn lại?

Bạn cung cấp ý định, ví dụ và đánh giá thiết kế. Agent chịu trách nhiệm chuyển chúng thành các artifact dưới đây khi đến giai đoạn phù hợp; không bắt bạn tự thiết kế kiến trúc hoặc tự viết mọi tài liệu.

| Artifact | Đầu vào | Khi cần |
| --- | --- | --- |
| Product requirements đã chốt | Q/B + PROJECT_PLAN | Trước tính năng tương ứng |
| User flows và state map | Hành vi queue/login/errors | Trước implement flow |
| Design spec và tokens | Ảnh chú thích + mockup đã chọn | Trước hoàn thiện UI |
| Data contracts / architecture ADR | Probe/API evidence + constraints | Trước port client/backend |
| Backlog task nhỏ có acceptance criteria | Plan + decisions | Trước agent loop |
| Test plan/corpus và device evidence | Link bài + checklist feasibility | Trong implementation/probe |
| Build/install guide | Project/scheme/signing thực tế | Khi có app build được |
| CHANGELOG / known limitations | Kết quả kiểm tra thật | Mỗi bản chia sẻ |
| Skills cục bộ | Quy trình đã chạy thành công | Khi workflow lặp lại ổn định |

Nội dung chưa có phải được ghi TBD/NOT TESTED. Không tạo cả chồng tài liệu rỗng hoặc đưa công cụ orchestration lên trước việc kiểm chứng playback.

## 8. Mẫu trả lời nhanh — có thể gửi trong chat

```text
1. Ba ưu tiên cao nhất: không có
2. Bản đầu bắt buộc có / có thể để sau: không có Tùy ý Agents
3. Đồng ý min OS 17 + giảm hiệu ứng trên máy cũ, hay chọn khác: đồng ý
4. Mở app vào đâu, có tự phát không:
5. Player: thích cụ thể những điểm nào của Apple Music: Có màn hình Lyrics chạy rất hay.
6. iPad: muốn bố cục player + lyrics thế nào:
7. Lyrics: ngôn ngữ, theo dòng/từng chữ, dịch/romanization:
8. Queue: tap bài thay queue? hết queue tự gợi ý hay dừng:
9. Ba điều không chấp nhận:
10. Ảnh/video/link tham khảo + điều thích/không thích:
11. Link bài hát công khai dùng thử: 
12. Dự kiến chia sẻ cho bao nhiêu người, máy/OS/Premium của họ:
13. Google login hay API trong Gemini; có cho phát sinh phí không: Google Login, có sẵn Pro, đừng phát sinh chi phí
14. Ngân sách/thời lượng/vòng sửa mong muốn cho hai agent: Ngân sách gồm hạn mức trong 5g. Tính tới 5g sáng nếu như đã hết chi phí thì không cần cố gắng để chạy thêm, trước khi kết thúc làm việc phải  để lại 1 bản handoff cho Người dùng đọc để biết tiến độ đang đi tới đâu. 
15. Có Developer membership? Cho tự commit local sau review không: https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player
Đây là đường link dẫn tới Repo trên github của tôi. Cần phải commit và push từng task mỗi khi code và test hoàn tất. KHÔNG CÓ NGOẠI LỆ. Phải comment tiếng Việt, đơn giản, dễ hiểu. 
```

Không có yêu cầu nào buộc phải trả lời cả 15 mục ngay. Có thể bắt đầu bằng 1, 2, 5, 6, 7 và 10 để chốt định hướng, rồi bổ sung các mục còn lại theo giai đoạn.
