library(lubridate)
library(tidyverse)
library(reshape)
library(tictoc)

# read raw data and extract date column
train_raw <- readr::read_csv(unz('train.csv.zip', 'train.csv'))
train_dates <- train_raw$Date

# training data from 2010-02 to 2011-02
start_date <- ymd("2010-02-01")
end_date <- start_date %m+% months(13)

# split dataset into training / testing
train_ids <- which(train_dates >= start_date & train_dates < end_date)
train = train_raw[train_ids, ]
test = train_raw[-train_ids, ]

# create the initial training data
readr::write_csv(train, 'train_ini.csv')

# create test.csv 
# remove weekly sales
test %>% 
  select(-Weekly_Sales) %>% 
  readr::write_csv('test.csv')

# create 10-fold time-series CV
num_folds <- 10
test_dates <- train_dates[-train_ids]

# month 1 --> 2011-03, and month 20 --> 2012-10.
# Fold 1 : month 1 & month 2, Fold 2 : month 3 & month 4 ...
for (i in 1:num_folds) {
  # filter fold for dates
  start_date <- ymd("2011-03-01") %m+% months(2 * (i - 1))
  end_date <- ymd("2011-05-01") %m+% months(2 * (i - 1))
  test_fold <- test %>%
    filter(Date >= start_date & Date < end_date)
  
  # write fold to a file
  readr::write_csv(test_fold, paste0('fold_', i, '.csv'))
}

train <- readr::read_csv('train_ini.csv')
test <- readr::read_csv('test.csv')

# save weighted mean absolute error WMAE
num_folds <- 10
wae <- rep(0, num_folds)

for (t in 1:10) {
  test_pred <- mypredict()
  
  # load fold file 
  fold_file <- paste0('fold_', t, '.csv')
  new_train <- readr::read_csv(fold_file, col_types = cols())
  
  # extract predictions matching up to the current fold
  scoring_tbl <- new_train %>% 
    left_join(test_pred, by = c('Date', 'Store', 'Dept'))
  
  # compute WMAE
  actuals <- scoring_tbl$Weekly_Sales
  preds <- scoring_tbl$Weekly_Pred
  preds[is.na(preds)] <- 0
  weights <- if_else(scoring_tbl$IsHoliday, 5, 1)
  wae[t] <- sum(weights * abs(actuals - preds)) / sum(weights)
}

mypredict = function(){
  # test data for first fold
  start_date <- ymd("2011-03-01") %m+% months(2 * (t - 1))
  end_date <- ymd("2011-05-01") %m+% months(2 * (t - 1))
  test_current <- test %>% filter(Date >= start_date & Date < end_date) %>% select(-IsHoliday) %>% mutate(Wk = week(Date))
  
  if (t > 1){
    train <<- train %>% add_row(new_train)
  }
  
  test_depts <- unique(test_current$Dept)
  test_pred <- NULL
  
  for(dept in test_depts){
    train_dept_data <- train %>% filter(Dept == dept)
    test_dept_data <- test_current %>% filter(Dept == dept)
    
    # use only unique stores present in both datasets
    train_stores <- unique(train_dept_data$Store)
    test_stores <- unique(test_dept_data$Store)
    test_stores <- intersect(train_stores, test_stores)
    
    for(store in test_stores){
      tmp_train <- train_dept_data %>% 
        filter(Store == store) %>%
        mutate(Wk = ifelse(year(Date) == 2010, week(Date)-1, week(Date))) %>%
        mutate(Yr = year(Date))
      tmp_test <- test_dept_data %>% 
        filter(Store == store) %>%
        mutate(Wk = ifelse(year(Date) == 2010, week(Date)-1, week(Date))) %>%
        mutate(Yr = year(Date)) 
      
      tmp_train$Wk = factor(tmp_train$Wk, levels = 1:52)
      tmp_test$Wk = factor(tmp_test$Wk, levels = 1:52)
      
      train_model_matrix <- model.matrix(~ Yr + Wk, tmp_train)
      test_model_matrix <- model.matrix(~ Yr + Wk, tmp_test)
      mycoef <- lm(tmp_train$Weekly_Sales ~ train_model_matrix)$coef
      mycoef[is.na(mycoef)] <- 0
      tmp_pred <- mycoef[1] + test_model_matrix %*% mycoef[-1]
      
      # shift predictions for the fifth fold
      if (t==5){
        tmp_test <- tmp_test %>%
          mutate(Weekly_Pred = tmp_pred[,1])
        
        if(52 %in% tmp_test$Wk & 51 %in% tmp_test$Wk){
          tmp_test[which(tmp_test$Wk == 52),]$Weekly_Pred <- tmp_test[tmp_test$Wk == 52,]$Weekly_Pred * (6/7) + 
            tmp_test[tmp_test$Wk == 51,]$Weekly_Pred * (1/7)
        }
        
        if(51 %in% tmp_test$Wk & 50 %in% tmp_test$Wk){
          tmp_test[which(tmp_test$Wk == 51),]$Weekly_Pred <- tmp_test[tmp_test$Wk == 51,]$Weekly_Pred * (6/7) + 
            tmp_test[tmp_test$Wk == 50,]$Weekly_Pred * (1/7)  
        }
        
        if(50 %in% tmp_test$Wk & 49 %in% tmp_test$Wk){
          tmp_test[which(tmp_test$Wk == 50),]$Weekly_Pred <- tmp_test[tmp_test$Wk == 50,]$Weekly_Pred * (6/7) + 
            tmp_test[tmp_test$Wk == 49,]$Weekly_Pred * (1/7)  
        }
        
        if(49 %in% tmp_test$Wk & 48 %in% tmp_test$Wk){
          tmp_test[which(tmp_test$Wk == 49),]$Weekly_Pred <- tmp_test[tmp_test$Wk == 49,]$Weekly_Pred * (6/7) + 
            tmp_test[tmp_test$Wk == 48,]$Weekly_Pred * (1/7)
        }
        
        tmp_test <- tmp_test %>%
          select(-Wk, -Yr)
      }else{
        tmp_test <- tmp_test %>%
          mutate(Weekly_Pred = tmp_pred[,1]) %>%
          select(-Wk, -Yr)
      }
      test_pred <- test_pred %>% bind_rows(tmp_test)
    }
  }
  return(test_pred)
