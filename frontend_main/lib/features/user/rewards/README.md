# Rewards (Đổi điểm thưởng)

## Mục tiêu
Màn hình danh sách đổi thưởng và luồng đổi điểm (redeem) dựa trên API `rewards/list` và `points/redeem`.

## Thành phần chính
- Data layer: models + remote datasource + repository.
- UI: `RewardsListScreen` + component `RewardItemCard`.

## Cách dùng nhanh
- Mở từ menu Profile: mục "Đổi điểm thưởng".
- App tự gọi API lấy danh sách quà tặng và số điểm hiện tại.
- Nhấn "Đổi" để redeem, sẽ hiển thị dialog chúc mừng kèm mã voucher.
