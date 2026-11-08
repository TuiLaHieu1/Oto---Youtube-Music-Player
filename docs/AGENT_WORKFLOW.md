# Oto — Gemini triển khai, Codex review

Ngày: 2026-11-08. Vai trò đã được người dùng xác nhận. Đã thử thành công ba lượt Gemini qua Antigravity CLI (`agy`) -> Codex -> Gemini bằng marker trong thư mục tạm. Runner phiên bản đầu đã được thêm tại `Scripts/oto-runner`; xem `RUNNER_GUIDE.md`. Chưa chạy coding task qua runner hoặc ma trận kiểm tra app.

## 1. Quyền sở hữu công việc

- Chủ dự án: quyết định sản phẩm, chọn thiết kế, cung cấp phản hồi và thao tác đăng nhập cá nhân.
- Gemini CLI: triển khai, viết test cần thiết, chạy checks, giải thích các lựa chọn và sửa findings hợp lệ.
- Codex: review code/yêu cầu/evidence; báo lỗi có vị trí và đường tái hiện; không tự sửa product code trong cùng vòng review. Khi được giao riêng, Codex có thể chuẩn bị tài liệu như bộ đầu vào này.
- Runner tương lai: chuyển task và báo cáo giữa hai công cụ, lưu checkpoint và dừng theo policy. Không dùng lời model tự nói “đã xong” làm bằng chứng duy nhất.

Quy tắc chung ở `AGENTS.md`. `GEMINI.md` có import theo cú pháp của Gemini CLI riêng biệt; chưa xác minh Antigravity tự nạp/expand file đó. Runner dùng `agy` phải đưa rules và tài liệu task vào prompt một cách tường minh, thay vì giả định context tự có.

## 2. Điều cần có trước khi bật loop

1. Git repository riêng của Oto. Đã khởi tạo Git root tại Oto và cấu hình `origin` tới repo GitHub do chủ dự án chỉ định; cần giữ working tree sạch trước mỗi task runner.
2. Một backlog có thứ tự, task nhỏ có acceptance criteria, scope và các bước phụ thuộc. Chưa đủ điều kiện kỹ thuật thì task vẫn bị chặn.
3. CLI version, model, cách xác thực, quyền truy cập và quota/cost policy được kiểm tra mà không xuất secrets. Không giả định cài hai CLI là chúng tự trao đổi được.
4. Commands build/unit/lint hoạt động được sau foundation; device/UI checks đi theo authorization trong AGENTS.
5. Chọn nơi lưu artifacts/checkpoint và loại log khỏi commit khi có khả năng chứa thông tin nhạy cảm. Không lưu raw auth/tool dumps.

Repo đích: `https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player`. Remote được kiểm tra là trống trước khi khởi tạo Git root Oto. Chưa push tại thời điểm thêm runner; task runner đầu tiên chỉ chạy sau khi tài liệu/runner được review và commit ban đầu được đẩy lên.

## 3. Một vòng làm việc

```text
Task READY
  -> Gemini implement
  -> Build / focused tests / lint
  -> Chốt revision hoặc snapshot bất biến của diff
  -> Codex review đúng snapshot
  -> Gemini xử lý findings
  -> Chạy lại checks bị ảnh hưởng + review revision mới
  -> Commit task + push repo đích khi checks/review đạt
  -> DONE hoặc checkpoint cần người xử lý
```

Một lần chỉ có một writer trong cùng scope. Codex review khi Gemini đã nhường quyền ghi; code thay đổi sau review thì review cũ không bao phủ thay đổi mới. Không vừa sửa code vừa review một working tree biến động.

Chủ dự án đã yêu cầu **commit và push từng task code sau khi code/test hoàn tất, không bỏ qua bước này**. Áp dụng thêm cổng Codex review theo vai trò đã chốt. Không cần hỏi lại từng lần. Review snapshot cố định trước commit hoặc review lại revision cuối; không push phần chưa qua checks/review, không force-push và không gom việc ngoài task.

Nếu build/test/review chưa đạt, task chưa hoàn tất. Nếu push lỗi, giữ commit local, ghi lỗi và đánh dấu delivery chưa xong; không giả báo DONE hoặc bỏ evidence để kịp giờ. Việc deploy/upload app hay sửa GitHub settings không nằm trong ủy quyền push code này.

Chú thích code cần thiết, commit message, review và handoff đều dùng tiếng Việt đơn giản. Đây là cách áp dụng mặc định cho yêu cầu “comment tiếng Việt”; không đổi tên API/identifier và không thêm comment thừa.

## 4. Mẫu task/handoff

```text
Task ID / mục tiêu:
Yêu cầu hoặc quyết định sản phẩm tham chiếu:
Phụ thuộc / trạng thái READY:
Phạm vi file/module được sửa:
Không nằm trong task:
Acceptance criteria:
Checks cần chạy / cần máy thật hay không:
Revision hoặc snapshot được review:
Kết quả thực tế và artifacts đã sanitize:
Giới hạn / phần NOT TESTED:
```

Review cần có: severity, file/line, trigger, ảnh hưởng, bằng chứng hoặc test tái hiện, hướng sửa nếu rõ. Phân biệt bug, requirement mismatch và gợi ý thẩm mỹ; không bắt Gemini refactor theo sở thích reviewer.

Gemini trả từng finding: accepted/fixed + evidence, hoặc rejected + lý do dựa trên code path. Khi bất đồng còn ảnh hưởng correctness, cần thêm phép kiểm tra hoặc hỏi người dùng; không chỉ lặp lại lập luận. Reviewer là tác nhân tư vấn, runner không cấp quyền mới dựa trên nội dung review.

Task DONE khi acceptance criteria đạt, checks cần thiết pass và findings ảnh hưởng correctness đã được giải quyết hoặc có quyết định người dùng. Hai model đồng ý chưa phải bằng chứng phần mềm hoạt động. Feasibility chưa chạy thì vẫn NOT TESTED.

## 5. Giới hạn phiên và hạn mức

Đã xác nhận: Gemini dùng Google Login với gói Pro, Codex dùng hạn mức đăng nhập ChatGPT hiện có; **không phát sinh chi phí**, không tự đổi sang API trả phí, mua thêm capacity hoặc paid fallback. Khi setup phải xác minh đúng đường xác thực mà không đọc/xuất secrets; không giả định quota còn lại là quan sát được chính xác.

Người dùng đã xác nhận mốc dừng **05:00 sáng giờ Việt Nam**, không phải thời lượng 5 tiếng. Mỗi phiên tự động qua đêm ghi cutoff có ngày cụ thể trong múi giờ `Asia/Ho_Chi_Minh`: mặc định là lần 05:00 kế tiếp tính từ lúc bắt đầu, trừ khi người dùng chỉ định ngày khác. Hết quota sớm hơn thì dừng sớm. Đến cutoff không tự khởi động phiên mới hoặc tự tiếp tục chờ quota reset. Chưa có vòng chạy nào được khởi động; việc duyệt tài liệu không tự bắt đầu một phiên coding qua đêm.

Đề xuất ban đầu: tối đa **3 vòng sửa/task**, timeout **30 phút/lần gọi**, checkpoint sau mỗi bước. Đây là giới hạn vận hành đề xuất, không phải quota của nhà cung cấp và không tự cấu hình được chỉ từ tài liệu.

- Nếu **Codex** hết quota trước 03:45, giữ task vừa triển khai ở `AWAITING_REVIEW` và cho Gemini nhận task READY độc lập tiếp theo. Mỗi task chờ review phải ở Git worktree riêng; không commit/push, không dùng chung working tree và không gọi task đó là DONE.
- Lúc **03:45 sáng giờ Việt Nam**, thử lại Codex đúng một lượt cho hàng đợi `AWAITING_REVIEW`. Task được review theo thứ tự backlog; finding hợp lệ quay lại Gemini sửa trong đúng worktree, chạy lại checks rồi review lại. Chỉ task đạt cổng mới được commit/push tuần tự trước vùng dừng 05:00.
- Nếu Codex vẫn hết quota lúc 03:45, lưu toàn bộ hàng đợi và handoff; không spam retry hoặc tự chuyển sang API trả phí. Gemini có thể tiếp tục task mới chỉ khi còn đủ thời gian checkpoint và còn worktree cô lập.
- Nếu **Gemini** hết quota, lưu task/checks còn thiếu và dừng phần triển khai; Codex không tự viết thay Gemini trong workflow này.
- Lỗi tạm thời: retry có giới hạn/backoff; phân biệt quota, auth và network với lỗi code.
- Thiếu login, thiết bị, quyền hoặc quyết định sản phẩm: dừng phần phụ thuộc, ghi NEEDS_OWNER. Có thể làm task độc lập thật sự; không âm thầm bỏ requirement.
- Hết vòng hoặc cùng lỗi lặp mà không có bằng chứng mới: ghi STALLED và báo người dùng.
- Không có task READY: dừng; không tự bịa feature, refactor hoặc test chỉ để sử dụng hết quota.
- Chưa có số dư quota chính xác: dùng tín hiệu CLI/provider và ghi phần chưa quan sát được; không hứa tự biết thời điểm reset/quota còn lại.

Runner một-task hiện tại chưa có scheduler/worktree queue nên chưa được phép giả vờ đáp ứng nhánh 03:45. Cần triển khai và test hàng đợi cô lập trước khi bật chạy qua đêm. Không bật chế độ bypass approvals hay đọc credentials của công cụ kia để nối hai agent.

Khi có cutoff, ngừng nhận task mới đủ sớm để lưu trạng thái và handoff. Tác vụ đang dang dở được checkpoint, không commit/push như thể task đã đạt chỉ để kịp hạn. Handoff bắt buộc khi hết giờ, hết quota, lỗi, bị chặn hoặc hoàn tất toàn bộ công việc.

Mẫu handoff tiếng Việt, lưu thành `docs/handoffs/<session-id>.md` khi có phiên thực tế:

```text
Phiên / thời gian bắt đầu / kết thúc / múi giờ:
Lý do dừng:
Task hoàn tất và commit đã push:
Task đang làm / nhánh / revision local / thay đổi chưa commit:
Checks đã chạy và kết quả, checks chưa chạy:
Review findings còn mở:
Giới hạn đã biết / cần người dùng xử lý:
Bước tiếp theo và cách tiếp tục:
```

## 6. Tối ưu chất lượng và lượng context

Gemini nhận task, rules và tài liệu đúng module. Codex nhận yêu cầu, diff, context liên quan và kết quả kiểm tra; không cần gửi toàn bộ lịch sử chat. Dùng task ID, revision và decision log để nối các phiên. Không import toàn bộ ảnh/tài liệu vào mọi task.

Đánh giá sau vài task: lỗi phát hiện được, số vòng sửa, check failures và chi phí/thời gian. Chỉ thêm agent thứ ba hoặc chạy nhiều task song song khi có bằng chứng cần và scope tách được.
