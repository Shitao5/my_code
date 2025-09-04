# 根据钉钉导出考勤数据的「每日统计」表和公司上下班节点
# 计算在公司的公司

library(tidyverse)
library(readxl)

file_path = "data/公司_考勤报表_20250801-20250831.xlsx"

morning_begin <- "09:00"
morning_end <- "12:00"
afternoon_begin <- "13:30"
afternoon_end <- "18:00"
night_begin <- "19:00"

parse_time <- function(d, t) {
  ymd_hm(paste(d, t, sep = " "), quiet = TRUE)
}

time_length_cal <- function(begin, end) {
  time_length(interval(begin, end), "minutes")
}

parse_punch <- function(d, t) {
  case_when(
    is.na(t) ~ NA_POSIXct_,
    str_detect(t, "^次日\\s*\\d{2}:\\d{2}$") ~
      ymd_hm(paste(d + days(1), str_extract(t, "\\d{2}:\\d{2}")), quiet = TRUE),
    str_detect(t, "^\\d{2}:\\d{2}$") ~
      ymd_hm(paste(d, t), quiet = TRUE),
    TRUE ~ NA_POSIXct_
  )
}

dt <- read_xlsx(file_path, sheet = "每日统计", skip = 2) |>
  filter(考勤组 != "未加入考勤组") |>
  select(
    姓名, 部门, 职位, 日期, 上班1打卡时间, 上班1打卡结果,
    下班1打卡时间, 下班1打卡结果, 关联的审批单
  ) |>
  mutate(
    周几 = str_extract(日期, "星期.{1}"),
    日期 = paste0("20", str_sub(日期, 1, 8)) |> ymd(),
    上班时间 = parse_punch(日期, 上班1打卡时间),
    下班时间 = parse_punch(日期, 下班1打卡时间),
    审批类型 = str_extract(关联的审批单, "^.*?(?=\\d{2}-\\d{2})"),
    审批起始时间 = parse_time(year(日期), str_extract(关联的审批单, "\\d{2}-\\d{2} \\d{2}:\\d{2}?(?=到)")),
    审批结束时间 = parse_time(year(日期), str_extract(关联的审批单, "(?<=到)\\d{2}-\\d{2} \\d{2}:\\d{2}")),
    上班时间 = case_when(
      !is.na(上班时间) ~ 上班时间,
      审批类型 %in% c("出差", "外出", "补卡申请", "加班") ~ 审批起始时间,
      审批类型 %in% c("年假", "事假", "病假", "调休") ~ NA,
      !is.na(下班时间) ~ parse_time(日期, morning_begin),
      .default = NA
    ),
    下班时间 = case_when(
      !is.na(下班时间) ~ 下班时间,
      审批类型 %in% c("出差", "外出", "补卡申请", "加班") ~ 审批结束时间,
      审批类型 %in% c("年假", "事假", "病假", "调休") ~ NA,
      !is.na(上班时间) ~ parse_time(日期, afternoon_end),
      .default = NA
    ),
    时长_上午 = case_when(
      is.na(上班时间) ~ 0,
      上班时间 >= parse_time(日期, morning_end) ~ 0,
      上班时间 <= parse_time(日期, morning_begin) & 下班时间 >= parse_time(日期, morning_end) ~
        time_length_cal(parse_time(日期, morning_begin), parse_time(日期, morning_end)),
      上班时间 > parse_time(日期, morning_begin) & 下班时间 >= parse_time(日期, morning_end) ~
        time_length_cal(上班时间, parse_time(日期, morning_end)),
      上班时间 <= parse_time(日期, morning_begin) & 下班时间 < parse_time(日期, morning_end) ~
        time_length_cal(parse_time(日期, morning_begin), 下班时间),
      上班时间 > parse_time(日期, morning_begin) & 下班时间 < parse_time(日期, morning_end) ~
        time_length_cal(上班时间, 下班时间)
    ),
    时长_下午 = case_when(
      is.na(下班时间) ~ 0,
      下班时间 <= parse_time(日期, afternoon_begin) ~ 0,
      下班时间 >= parse_time(日期, afternoon_end) & 上班时间 <= parse_time(日期, afternoon_begin) ~
        time_length_cal(parse_time(日期, afternoon_begin), parse_time(日期, afternoon_end)),
      下班时间 >= parse_time(日期, afternoon_end) & 上班时间 > parse_time(日期, afternoon_begin) ~
        time_length_cal(上班时间, parse_time(日期, afternoon_end)),
      下班时间 < parse_time(日期, afternoon_end) & 上班时间 <= parse_time(日期, afternoon_begin) ~
        time_length_cal(parse_time(日期, afternoon_begin), 下班时间),
      下班时间 < parse_time(日期, afternoon_end) & 上班时间 > parse_time(日期, afternoon_begin) ~
        time_length_cal(上班时间, 下班时间)
    ),
    时长_晚上 = case_when(
      is.na(下班时间) ~ 0,
      下班时间 <= parse_time(日期, night_begin) ~ 0,
      .default = time_length_cal(parse_time(日期, night_begin), 下班时间)
    ),
    工作时长 = 时长_上午 + 时长_下午 + 时长_晚上
  ) 
