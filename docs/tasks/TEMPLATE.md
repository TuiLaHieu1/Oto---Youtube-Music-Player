# TASK-[CATEGORY]-[NUMBER]: [Tiêu đề Task Ngắn gọn]

## 1. Hiện tượng & Vấn đề (Problem Statement)
Mô tả rõ lỗi hoặc hành vi quan sát được trên thiết bị thật hoặc trong runtime.

## 2. Cách tái hiện (Reproduction Steps)
1. Bước 1...
2. Bước 2...
3. Bước 3...

## 3. Kết quả mong đợi (Expected Behavior)
- Hành vi mong muốn của hệ thống...

## 4. Kết quả thực tế (Actual Behavior)
- Hiện tượng lỗi đang xảy ra...

## 5. Bằng chứng hiện có (Evidence)
- **Thiết bị kiểm thử:** (ví dụ: iPhone 13 Pro Max - iOS 18.x)
- **Log đã sanitize:** (Trích log liên quan, che giấu token/cookie)
- **Screenshot / Video:** (Đường dẫn hoặc mô tả)

## 6. Phạm vi cho phép (In Scope)
- Danh sách file hoặc module được phép sửa:
  - `Oto/...`
  - `Packages/OtoCore/...`

## 7. Ngoài phạm vi (Out of Scope)
- Không refactor các màn hình không liên quan.
- Không sửa logic authentication nếu task chỉ thuộc về player UI.

## 8. Tiêu chí nghiệm thu (Acceptance Criteria)
- [ ] Logic unit test & regression test pass.
- [ ] Build generic iOS và simulator thành công.
- [ ] SwiftLint strict 0 lỗi.
- [ ] Kiểm thử trên thiết bị thật đạt kết quả (hoặc ghi rõ lý do chưa thể test).

## 9. Bảng nghiệm thu hoàn tất (Sign-off Table)

| Tiêu chí nghiệm thu | Trạng thái (PASS / FAIL / NOT TESTED) | Bằng chứng kiểm tra |
| :--- | :---: | :--- |
| Unit Tests (`swift test` / `xcodebuild test`) | ... | ... |
| Lint & Build Verification | ... | ... |
| Kiểm thử trên iPhone thật | ... | ... |

> [!NOTE]
> **Điều kiện DONE:** Task không được coi là DONE nếu hàng mục kiểm thử phần cứng liên quan còn mang trạng thái `NOT TESTED`. Nếu chỉ hoàn thành mã nguồn, trạng thái tối đa là `CODE COMPLETE (DEVICE TEST REQUIRED)`.
