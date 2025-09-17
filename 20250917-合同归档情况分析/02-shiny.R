# app.R
library(shiny)
library(tidyverse)
library(readxl)
library(writexl)

# ======================= 数据处理函数 ============================
get_ywlz <- function(path) {
  target_cols <- c("审批编号", "审批状态", "审批结果",  
                   "发起人部门", "发起人姓名", 
                   "发起时间", "对方单位名称", "合作产品类型", "用印类型",
                   "审批记录(含处理人UserID)")
  sheets <- excel_sheets(path)
  
  map(sheets, \(x) read_xlsx(path, sheet = x)) |> 
    list_rbind() |> 
    select(any_of(target_cols)) |> 
    arrange(发起时间)
}

process_ywlz <- function(dt_ywlz) {
  dt_ywlz |>
    mutate(
      状态 = case_when(
        审批状态 == "完成" & 审批结果 == "同意" ~ "已归档",
        审批状态 == "审批中" &
          !str_detect(`审批记录(含处理人UserID)`, "行政合同归档") &
          str_detect(`审批记录(含处理人UserID)`, "用印审核|用印审批") ~ "已用印未归档",
        .default = NA_character_
      ),
      归档起始时间 = if_else(
        is.na(状态),
        NA_character_,
        str_extract(
          `审批记录(含处理人UserID)`,
          "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}(?=[^0-9]*$)"
        )
      ),
      用印主体 = str_extract(用印类型, "^[^-]+(?=-[^章]*章)|(?<=章-)[^-]+$")
    ) |> 
    select(-c(`审批记录(含处理人UserID)`), 用印主体)
}

# ======================= Shiny 应用 ==============================
ui <- fluidPage(
  titlePanel("业务流转Excel处理工具"),
  sidebarLayout(
    sidebarPanel(
      fileInput("file", "上传Excel文件", 
                accept = c(".xlsx")),
      downloadButton("download", "下载处理结果")
    ),
    mainPanel(
      h4("预览处理结果（前50行）："),
      tableOutput("preview")
    )
  )
)

server <- function(input, output, session) {
  
  data_processed <- reactive({
    req(input$file)
    dt <- get_ywlz(input$file$datapath)
    process_ywlz(dt)
  })
  
  output$preview <- renderTable({
    head(data_processed(), 50)
  })
  
  output$download <- downloadHandler(
    filename = function() {
      paste0("res_", Sys.Date(), ".xlsx")
    },
    content = function(file) {
      writexl::write_xlsx(data_processed(), file)
    }
  )
}

shinyApp(ui, server)
