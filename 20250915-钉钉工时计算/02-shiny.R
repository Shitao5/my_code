# app.R
options(shiny.maxRequestSize = 100*1024^2)

suppressPackageStartupMessages({
  library(shiny)
  library(tidyverse)
  library(readxl)
  library(lubridate)
  library(DT)
  library(writexl)
  library(stringr)
})

ui <- fluidPage(
  titlePanel("钉钉考勤分析（上传报表 → 设置阈值 → 查看与下载结果）"),
  sidebarLayout(
    sidebarPanel(
      fileInput("file", "上传钉钉考勤报表（.xlsx，sheet 为“每日统计”）", accept = c(".xlsx")),
      tags$hr(),
      h4("工作天数计入阈值（分钟）"),
      numericInput("day_morning", "上午计入 0.5 天的最少分钟数", value = 2*60, min = 0, step = 5),
      numericInput("day_afternoon", "下午计入 0.5 天的最少分钟数", value = 3.5*60, min = 0, step = 5),
      tags$hr(),
      downloadButton("download", "下载最终结果（含每日明细与每月汇总）", class = "btn-primary")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("每月工作时长/工作天数汇总", DTOutput("tbl_month")),
        tabPanel("每日工作时长明细", DTOutput("tbl_daily"))
      )
    )
  )
)

server <- function(input, output, session){
  
  # 固定的时间段（与原脚本一致）
  morning_begin   <- "09:00"
  morning_end     <- "12:00"
  afternoon_begin <- "13:30"
  afternoon_end   <- "18:00"
  night_begin     <- "19:00"
  
  # --------- 工具函数（与原脚本一致/等价） ----------
  parse_time <- function(d, t) {
    # d: Date 或 年份（见下面审批解析处保持你脚本的用法）
    # t: "MM-DD HH:MM" 或 "HH:MM"
    ymd_hm(paste(d, t, sep = " "), quiet = TRUE)
  }
  
  time_length_cal <- function(begin, end) {
    time_length(interval(begin, end), "minutes")
  }
  
  parse_punch <- function(d, t) {
    case_when(
      is.na(t) ~ lubridate::NA_POSIXct_,
      str_detect(t, "^次日\\s*\\d{2}:\\d{2}$") ~
        ymd_hm(paste(d + days(1), str_extract(t, "\\d{2}:\\d{2}")), quiet = TRUE),
      str_detect(t, "^\\d{2}:\\d{2}$") ~
        ymd_hm(paste(d, t), quiet = TRUE),
      TRUE ~ lubridate::NA_POSIXct_
    )
  }
  
  # 读取并计算（响应式）
  dat_calculated <- reactive({
    req(input$file)
    
    # 读取原始数据
    df_raw <- tryCatch(
      read_xlsx(input$file$datapath, sheet = "每日统计", skip = 2),
      error = function(e) NULL
    )
    validate(need(!is.null(df_raw), "无法读取 sheet = '每日统计'。请检查文件是否正确。"))
    
    # 必要列检查（尽量贴合你脚本使用到的列）
    need_cols <- c("姓名","部门","职位","日期",
                   "上班1打卡时间","上班1打卡结果",
                   "下班1打卡时间","下班1打卡结果",
                   "关联的审批单","考勤组")
    missing_cols <- setdiff(need_cols, names(df_raw))
    validate(need(length(missing_cols) == 0,
                  paste0("缺少必要列：", paste(missing_cols, collapse = "，"))))
    
    # 过滤并选择列
    dt <- df_raw |>
      filter(考勤组 != "未加入考勤组") |>
      select(
        姓名, 部门, 职位, 日期,
        上班1打卡时间, 上班1打卡结果,
        下班1打卡时间, 下班1打卡结果,
        关联的审批单
      ) |>
      mutate(
        周几 = str_extract(日期, "星期.{1}"),
        日期 = paste0("20", str_sub(日期, 1, 8)) |> ymd(),
        上班时间 = parse_punch(日期, 上班1打卡时间),
        下班时间 = parse_punch(日期, 下班1打卡时间),
        审批类型 = str_extract(关联的审批单, "^.*?(?=\\d{2}-\\d{2})"),
        # 这里保持你脚本“parse_time(year(日期), 'MM-DD HH:MM')”的写法
        审批起始时间 = parse_time(year(日期), str_extract(关联的审批单, "\\d{2}-\\d{2} \\d{2}:\\d{2}?(?=到)")),
        审批结束时间 = parse_time(year(日期), str_extract(关联的审批单, "(?<=到)\\d{2}-\\d{2} \\d{2}:\\d{2}"))
      ) |>
      mutate(
        上班时间 = case_when(
          !is.na(上班时间) ~ 上班时间,
          审批类型 %in% c("出差", "外出", "补卡申请", "加班") &
            日期 > as_date(审批起始时间) & 日期 <= as_date(审批结束时间) ~ parse_time(日期, morning_begin),
          审批类型 %in% c("出差", "外出", "补卡申请", "加班") &
            日期 == as_date(审批起始时间) & 日期 <= as_date(审批结束时间) ~ 审批起始时间,
          审批类型 %in% c("年假", "事假", "病假", "调休") & is.na(下班时间) ~ NA,
          审批类型 %in% c("年假", "事假", "病假", "调休") & !is.na(下班时间) ~ parse_time(日期, afternoon_begin),
          !is.na(下班时间) ~ parse_time(日期, morning_begin),
          .default = NA
        ),
        下班时间 = case_when(
          !is.na(下班时间) ~ 下班时间,
          审批类型 %in% c("出差", "外出", "补卡申请", "加班") &
            日期 >= as_date(审批起始时间) & 日期 < as_date(审批结束时间) ~ parse_time(日期, afternoon_end),
          审批类型 %in% c("出差", "外出", "补卡申请", "加班") &
            日期 >= as_date(审批起始时间) & 日期 == as_date(审批结束时间) ~ 审批结束时间,
          审批类型 %in% c("年假", "事假", "病假", "调休") & is.na(上班时间) ~ NA,
          审批类型 %in% c("年假", "事假", "病假", "调休") & !is.na(上班时间) ~ parse_time(日期, morning_end),
          !is.na(上班时间) ~ parse_time(日期, afternoon_end),
          .default = NA
        )
      ) |>
      mutate(
        时长_上午 = case_when(
          is.na(上班时间) ~ 0,
          上班时间 >= parse_time(日期, morning_end) ~ 0,
          上班时间 <= parse_time(日期, morning_begin) & 下班时间 >= parse_time(日期, morning_end) ~
            time_length_cal(上班时间, parse_time(日期, morning_end)),
          上班时间 > parse_time(日期, morning_begin) & 下班时间 >= parse_time(日期, morning_end) ~
            time_length_cal(上班时间, parse_time(日期, morning_end)),
          上班时间 <= parse_time(日期, morning_begin) & 下班时间 < parse_time(日期, morning_end) ~
            time_length_cal(上班时间, 下班时间),
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
    
    # 汇总（使用输入的阈值：分钟）
    dt_month <- dt |>
      summarise(
        .by = c(部门, 姓名),
        工作时长 = round(sum(工作时长, na.rm = TRUE) / 60, 2),
        工作天数 = sum(
          ifelse(时长_上午 >= input$day_morning, 0.5, 0),
          ifelse(时长_下午 >= input$day_afternoon, 0.5, 0)
        )
      ) |>
      arrange(部门, 姓名)
    
    list(dt_daily = dt, dt_month = dt_month)
  })
  
  # 显示每月汇总
  output$tbl_month <- renderDT({
    req(dat_calculated())
    datatable(
      dat_calculated()$dt_month,
      rownames = FALSE,
      extensions = "Buttons",
      options = list(
        dom = "Bfrtip",
        buttons = c("copy", "csv", "excel"),
        pageLength = 20
      )
    )
  })
  
  # 显示每日明细
  output$tbl_daily <- renderDT({
    req(dat_calculated())
    datatable(
      dat_calculated()$dt_daily,
      rownames = FALSE,
      extensions = "Buttons",
      options = list(
        dom = "Bfrtip",
        buttons = c("copy", "csv", "excel"),
        pageLength = 20,
        scrollX = TRUE
      )
    )
  })
  
  # 下载结果（两个 sheet）
  output$download <- downloadHandler(
    filename = function(){
      paste0("钉钉考勤分析结果_", format(Sys.Date(), "%Y%m%d"), ".xlsx")
    },
    content = function(file){
      req(dat_calculated())
      writexl::write_xlsx(
        list(
          每日工作时长明细 = dat_calculated()$dt_daily,
          每月工作时长 = dat_calculated()$dt_month
        ),
        path = file
      )
    }
  )
}

shinyApp(ui, server)
