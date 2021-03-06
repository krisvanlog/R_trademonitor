
# (C) 2018 Vladimir Zhbanko 
# Shiny app to monitor statistics of the trading systems
# Course Lazy Trading Part 3: Set up your automated Trading Journal


library(shinydashboard)
library(tidyverse)
library(lubridate)
library(readxl)
library(DT)
library(xlsx)

#=============================================================
#========= FUNCTIONS AND VARIABLES============================
#=============================================================


# specifying the path to the 4x terminals used into the dataframe
Terminals <- data.frame(id = 1:4, TermPath = c("C:/Program Files (x86)/MT4_Terminal_1/MQL4/Files/",
                                               "C:/Program Files (x86)/MT4_Terminal_2/MQL4/Files/",
                                               "C:/Program Files (x86)/MT4_Terminal_3/MQL4/Files/",
                                               "C:/Program Files (x86)/MT4_Terminal_4/MQL4/Files/"),
                                               
                        stringsAsFactors = F)

# -------------------------------
# load prices of 28 currencies
# if file is not found in the terminal sandbox, retrieve it from working directory
prices <- read_csv(file.path(Terminals[1,2], "AI_CP15-14200.csv"), col_names = FALSE)
# make the price having proper format
prices$X1 <- ymd_hms(prices$X1)

# Vector of currency pairs
Pairs = c("Date", "AUDUSD", "AUDCHF", "AUDCAD", "AUDNZD")   
# Rename the column?
names(prices) <- Pairs
# -------------------------------
# Load tables with trading strategies
Strategies <- read_excel("Strategies.xlsx",sheet = 1,col_names = TRUE)
Strategies$ID <- as.factor(Strategies$ID)
# -------------------------------
# function that write data to csv file 
storeData <- function(data, fileName) {
  
  # store only unique records
  # non duplicates
  nonDuplicate <- data[!duplicated(data), ]
  # Write the file to the local system
  write.csv(
    x = nonDuplicate,
    file = fileName, 
    row.names = FALSE, quote = FALSE, append = TRUE, col.names = FALSE
  )
}

# ============================================================

shinyServer(function(input, output, session) {

  #=============================================================
  #========= REACTIVE VALUES ===================================
  #=============================================================  
  
  #---------------------  
  # have a reactive value of terminal number selected
  file_path <- reactive({ file_path <- paste0(Terminals[input$TermNum, 2], "OrdersResultsT", input$TermNum,".csv") })
  #Debugging: file_path <- paste0(Terminals[1, 2], "OrdersResultsT", 1,".csv")
  # # No DSS? Uncomment and use this variable instead:
  #file_path <- reactive({ file_path <- paste0("OrdersResultsT", input$TermNum,".csv") })
  
  #---------------------
  # have a reactive value of the magic system selected
  system_analysed <- reactive({ system_analysed <- input$MagicNum })
  
  #---------------------
  # have a reactive value of the strategy type
  strategy_analysed <- reactive({ system_analysed() %>% substr(4,5) })
  
  #---------------------
  # cleaning data and creating relevant statistics
  DF_Stats <- reactive({ 
                        DF_Stats <- read_csv(file = file_path(), col_names = F)
                        #DF_Stats <- read_csv(file = file_path, col_names = F)
                        DF_Stats$X3 <- ymd_hms(DF_Stats$X3)
                        DF_Stats$X4 <- ymd_hms(DF_Stats$X4)
                        DF_Stats <- DF_Stats %>%
                        filter(X3 > as.POSIXct(input$filterDate)) %>% 
                        group_by(X1) %>%
                        summarise(PnL = sum(X5),
                                  NumTrades = n()) %>% 
                          arrange(X1) %>% 
                        filter(NumTrades > input$nTrades[1], NumTrades < input$nTrades[2]) %>% 
                        filter(PnL > input$filter[1], PnL < input$filter[2])   
                      })
  
  #---------------------
  # make summary statistics of all systems PnL
  DF_Stats_PnL <- reactive({ 
    DF_Stats_PnL <- read_csv(file = file_path(), col_names = F)
    #DF_Stats_PnL <- read_csv(file = file_path, col_names = F)
    DF_Stats_PnL$X3 <- ymd_hms(DF_Stats_PnL$X3)
    DF_Stats_PnL$X4 <- ymd_hms(DF_Stats_PnL$X4)
    DF_Stats_PnL <- DF_Stats_PnL %>%
      filter(X3 > as.POSIXct(input$filterDate)) %>% 
      group_by(X1) %>%
      summarise(PnL = sum(X5),
                NumTrades = n()) %>% 
      arrange(X1) %>% 
      filter(NumTrades > input$nTrades[1], NumTrades < input$nTrades[2]) %>% 
      filter(PnL > input$filter[1], PnL < input$filter[2]) %>% 
      summarise(TotPnL = sum(PnL),
                NumTrades = sum(NumTrades))
  })
  
  #---------------------
  # make strategy table (to derive it from magic number)
  Strategy <- reactive({ Strategies %>% filter(ID == strategy_analysed()) })
  
  #---------------------
  # store record as reactive value
  DF <- reactive({ 
    
    DF <- data.frame(ID = strategy_analysed(), Date = as.character(Sys.Date()), Log = as.character(input$caption))
    
    })
  
  
  
  #=============================================================
  #========= REACTIVE EVENTS ===================================
  #=============================================================  
  # import the summary statistics on the beginning of the app, call the statistics on refresh button call
  observeEvent(input$Refresh, {

    # update the magic numbers selection
    updateSelectInput(session, inputId = "MagicNum", label = NULL, choices = unique(DF_Stats()$X1), selected = NULL)
    
      #try to read from file responses.csv first for the information that is already available
    DF <- try(read_csv(file = "responses.csv", col_types = "ccc"),silent = T)
      
      if (class(DF)[3] == "data.frame") {    # get data from file to the responses
        responses <<- DF
      }
  })
  
  # add record to the log file and write that to the file back, delete content from the input text
  observeEvent(input$subm_rec, {
   
    #add record to log object
    # function that write data to global directory called "responses"
    saveDataGlobal <- function(data) {
      
      if (exists("responses")) {    # get data from global environment is it's exist there
        responses <<- rbind(responses, data)
      } else {
        responses <<- data                # <<- this saves to the global environment
      }
    }
    
    # save data to global directory
    saveDataGlobal(DF())
    
    #write to file (append)
    storeData(responses, "responses.csv") 
    #eraze what was written
    updateTextAreaInput(session, inputId = "caption", label = NULL, value = "")
    
  })
  
  
#=============================================================
#========= OUTPUTS ===========================================
#=============================================================
  
  # -------------------------------------------
  # generating plot 1 statistics of the terminal
  output$plot1 <- renderPlot({

    DF_Stats() %>% 
      #DF_Stats %>% #debugging
      ggplot(aes(x = PnL, y = as.factor(X1), size = NumTrades)) + geom_point()+ 
      ggtitle(label = "Plot indicating which systems are profitable", 
              subtitle = "Size of the point represent number of trades completed") +
      geom_vline(xintercept=0, linetype="dashed", color = "green") +
      geom_vline(xintercept = DF_Stats_PnL()$TotPnL, color = "red")

    })
  
  # -------------------------------------------
  # table with statistic of the system, P/L and Number of trades
  output$statistics <- renderTable({  DF_Stats() %>%  filter(X1 == system_analysed())   })
  
  # -------------------------------------------
  # table with statistic of the system, Sum PnL and N trades
  output$summary <- renderTable({   DF_Stats_PnL()  })
  
  # -------------------------------------------
  # generating plot 2 statistics of the system
  output$plot2 <- renderPlot({
    
    DF <- read_csv(file = file_path(), col_names = F)
    DF$X3 <- ymd_hms(DF$X3)
    DF$X4 <- ymd_hms(DF$X4)
    DF %>%
      # only show one system
      filter(X1 == system_analysed()) %>%
      # filter by date, this allows to see trends better!!!
      filter(X4 > as.POSIXct(input$filterDate)) %>% 
      # bring the plot...
      ggplot(aes(x = X4, y = X5, col = as.factor(X7), shape = as.factor(X6))) + geom_point()+ 
      # this is just a line separating profit and loss :)
      geom_hline(yintercept=0, linetype="dashed", color = "red")+
      # adding a simple line summarising points, user can select if apply stat.error filter
      geom_smooth(method = "lm", se = input$StatErr)
    
  })
  
  # # -------------------------------------------
  # generating plot 3 price chart of pairs
  output$plot3 <- renderPlot({
    
    DF <- read_csv(file = file_path(), col_names = F)
    DF$X3 <- ymd_hms(DF$X3)
    DF$X4 <- ymd_hms(DF$X4)
    
    # find the oldest trade done
    DF1 <- DF %>% 
      # only show one system
      filter(X1 == system_analysed()) %>% 
      select(X4) %>% arrange() %>% head(1)
    FirstTrade <- DF1$X4
    
    # find the currency which is in trade
    DF2 <- DF %>% 
      # only show one system
      filter(X1 == system_analysed()) %>% 
      select(X6) %>% head(1)
    Currency <- DF2$X6
    
    # extract relevant price information...
    DF_Date <- subset(prices, select = Date)
    DF_Price <- subset(prices, select = Currency) %>% bind_cols(DF_Date)
    
    # rename otherwise ggplot did not work
    names(DF_Price) <- c("X1", "Date")
    
    # bring the plot...
    DF_Price %>% filter(Date > as.POSIXct(FirstTrade)) %>%
      select(Date, X1) %>% 
      ggplot(aes(Date, X1, col = "red")) + geom_line()
    
  })
  
  # generating strategy output
  output$strategy_text <- renderTable({ Strategy() })
  
  # function that visualizes the current table results if it's stored in GLobal Environment
  loadData <- function() {
    if (exists("responses")) {
      responses
    }
  }
  # writing logs of the records
  output$mytable <- DT::renderDataTable({
    
    input$subm_rec
    loadData()
  })
  
})
