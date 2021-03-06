#Timing the entire procedure to compare with earlier classifiers.

start.time <- Sys.time()

library(caret)
library(plyr)
library(dplyr)
library(xgboost)
library(Metrics)
library(doMC)
library(parallelMap)
library(parallel)

registerDoMC(cores = detectCores())

#The training and testing datasets are read into R and then prepared for the model building phase.

train.raw.origional <- read.csv("C:/Users/Mark/Documents/creditcard/train.csv",stringsAsFactors = FALSE)

train.raw.origional <- train.raw.origional[,-1]

#Test whether normalising the Amount and Time variables helps prediction accuracy. 

#train.raw.origional$Amount <- scale(train.raw.origional$Amount)

#train.raw.origional$Time <- scale(train.raw.origional$Time)

test.raw.class <- read.csv("C:/Users/Mark/Documents/creditcard/test_data_Class.csv",stringsAsFactors = FALSE)

test.raw <- read.csv("C:/Users/Mark/Documents/creditcard/test_NoClass.csv",stringsAsFactors = FALSE)

test.raw <- test.raw[,-1]

test.raw$Time <- as.numeric(test.raw$Time)

#Test whether normalising the Amount and Time variables helps prediction accuracy. 

#test.raw$Amount <- scale(test.raw$Amount)

#test.raw$Time <- scale(test.raw$Time)

prepL0FeatureSet1 <- function(df) {
  id <- df$id
  if (class(df$Class) != "NULL") {
    y <- df$Class
  } else {
    y <- NULL
  }
  
  predictor_vars <- c(CONFIRMED_ATTR)
  
  predictors <- df[predictor_vars]
  
  # for numeric set missing values to -1 for purposes
  num_attr <- intersect(predictor_vars,DATA_ATTR_TYPES$numeric)
  for (x in num_attr){
    predictors[[x]][is.na(predictors[[x]])] <- -1
  }
  
  # for character  atributes set missing value
  char_attr <- intersect(predictor_vars,DATA_ATTR_TYPES$character)
  for (x in char_attr){
    predictors[[x]][is.na(predictors[[x]])] <- "*MISSING*"
    predictors[[x]] <- factor(predictors[[x]])
  }
  
  return(list(id=id,y=y,predictors=predictors))
}

prepL0FeatureSet2 <- function(df) {
  id <- df$id
  if (class(df$Class) != "NULL") {
    y <- df$Class
  } else {
    y <- NULL
  }
  
  
  predictor_vars <- c(CONFIRMED_ATTR)
  
  predictors <- df[predictor_vars]
  
  # for numeric set missing values to -1 for purposes
  num_attr <- intersect(predictor_vars,DATA_ATTR_TYPES$numeric)
  for (x in num_attr){
    predictors[[x]][is.na(predictors[[x]])] <- -1
  }
  
  # for character  atributes set missing value
  char_attr <- intersect(predictor_vars,DATA_ATTR_TYPES$character)
  for (x in char_attr){
    predictors[[x]][is.na(predictors[[x]])] <- "*MISSING*"
    predictors[[x]] <- as.numeric(factor(predictors[[x]]))
  }
  
  return(list(id=id,y=y,predictors=as.matrix(predictors)))
}

#train model on one data fold
trainOneFold <- function(this_fold,feature_set) {
  # get fold specific cv data
  cv.data <- list()
  cv.data$predictors <- feature_set$train$predictors[this_fold,]
  cv.data$id <- feature_set$train$id[this_fold]
  cv.data$y <- feature_set$train$y[this_fold]
  
  # get training data for specific fold
  train.data <- list()
  train.data$predictors <- feature_set$train$predictors[-this_fold,]
  train.data$y <- feature_set$train$y[-this_fold]
  
  
  set.seed(825)
  fitted_mdl <- do.call(train,
                        c(list(x=train.data$predictors,y=train.data$y),
                          CARET.TRAIN.PARMS,
                          MODEL.SPECIFIC.PARMS,
                          CARET.TRAIN.OTHER.PARMS))
  
  yhat <- predict(fitted_mdl,newdata = cv.data$predictors,type = "prob")
  
  yhat <- as.factor(ifelse(yhat$Bad > 0.5,'Bad','Good'))
  
  precision <- posPredValue(yhat, cv.data$y, positive = "Bad")
  
  recall <- sensitivity(yhat, cv.data$y, positive = "Good")
  
  score <- (2 * precision * recall) / (precision + recall)
  
  ans <- list(fitted_mdl=fitted_mdl,
              score=score,
              predictions=data.frame(id=cv.data$id,yhat=yhat,y=cv.data$y))
  
  return(ans)
  
}

# make prediction from a model fitted to one fold
makeOneFoldTestPrediction <- function(this_fold,feature_set) {
  
  fitted_mdl <- this_fold$fitted_mdl
  
  yhat <- predict(fitted_mdl,newdata = feature_set$test$predictors,type = "prob")
  
  yhat <- as.factor(ifelse(yhat$Bad > 0.5,'Bad','Good'))
  
  return(yhat)
}

train.raw <- read.csv("C:/Users/Mark/Documents/creditcard/train_tomek_smote.csv",stringsAsFactors = FALSE)

train.raw <- train.raw[,-1]

train.raw_id <- seq(1,dim(train.raw)[1],length=dim(train.raw)[1])	

train.raw <- cbind(id=as.integer(train.raw_id),train.raw)

train.raw$Class <- as.factor(ifelse(train.raw$Class == 0,'Good', 'Bad'))

train.raw$Time <- scale(train.raw$Time)

train.raw$Amount <- scale(train.raw$Amount)

Predictions <- data.frame(test.raw$id)

F1_scores_train <- list()

for(i in c(1:10)){
  
  CONFIRMED_ATTR <- colnames(train.raw)
  
  CONFIRMED_ATTR <- CONFIRMED_ATTR[2:31]
  
  REJECTED_ATTR <-  setdiff(colnames(train.raw),CONFIRMED_ATTR)
  
  PREDICTOR_ATTR <- c(CONFIRMED_ATTR,REJECTED_ATTR)
  
  # Determine data types in the data set
  data_types <- sapply(PREDICTOR_ATTR,function(x){class(train.raw[[x]])})
  unique_data_types <- unique(data_types)
  
  # Separate attributes by data type
  DATA_ATTR_TYPES <- lapply(unique_data_types,function(x){ names(data_types[data_types == x])})
  names(DATA_ATTR_TYPES) <- unique_data_types
  
  # # create folds for training
  # set.seed(13)
  # data_folds <- createFolds(train.raw$Class, k=5)
  # 
  # L0FeatureSet1 <- list(train=prepL0FeatureSet1(train.raw),
  #                       test=prepL0FeatureSet1(test.raw))
  
  L0FeatureSet2 <- list(train=prepL0FeatureSet2(train.raw),
                        test=prepL0FeatureSet2(test.raw))
  
  # set caret training parameters
  CARET.TRAIN.PARMS <- list(method="xgbTree")   
  
  CARET.TUNE.GRID <-  expand.grid(nrounds=1000,
                                  max_depth=6,
                                  eta=0.3,
                                  gamma=1.34,
                                  colsample_bytree=0.678,
                                  min_child_weight=6.22)
  #,subsample=0.876)
  
  MODEL.SPECIFIC.PARMS <- list(verbose=0) #NULL # Other model specific parameters
  
  # model specific training parameter
  CARET.TRAIN.CTRL <- trainControl(method="none",
                                   verboseIter=TRUE,
                                   classProbs=TRUE,
                                   allowParallel=TRUE)
  
  CARET.TRAIN.OTHER.PARMS <- list(trControl=CARET.TRAIN.CTRL,
                                  tuneGrid=CARET.TUNE.GRID,
                                  metric="Sens")
  
  # # generate Level 1 features
  # xgb_set <- llply(data_folds,trainOneFold,L0FeatureSet2)
  
  # final model fit
  xgb_mdl <- do.call(train,
                     c(list(x=L0FeatureSet2$train$predictors,y=L0FeatureSet2$train$y),
                       CARET.TRAIN.PARMS,
                       MODEL.SPECIFIC.PARMS,
                       CARET.TRAIN.OTHER.PARMS))
  
  train_xgb_yhat <- predict(xgb_mdl,newdata = train.raw.origional[,c(-1,-31)],type = "prob")
  
  train_xgb_yhat <- as.factor(ifelse(train_xgb_yhat$Bad > 0.5,'1','0'))
  
  precision <- posPredValue(train_xgb_yhat, as.factor(train.raw.origional$Class), positive = "1")
  
  recall <- sensitivity(train_xgb_yhat, as.factor(train.raw.origional$Class), positive = "1")
  
  score_train <- (2 * precision * recall) / (precision + recall)
  
  cat("XGB Train: (F1 score, Precision, Recall):", score_train, precision, recall,"\n")
  
  cat("Dim XGB Train: ", dim(train.raw),(dim(train.raw)[1])*100/dim(train.raw.origional)[1],"\n")
  
  F1_scores_train[i] <- as.numeric(score_train)
  
  test_xgb_yhat <- predict(xgb_mdl,newdata = L0FeatureSet2$test$predictors,type = "prob")
  
  test_xgb_yhat <- as.factor(ifelse(test_xgb_yhat$Bad > 0.5,'1','0'))
  
  precision <- posPredValue(test_xgb_yhat, as.factor(test.raw.class$Class), positive = "1")
  
  recall <- sensitivity(test_xgb_yhat, as.factor(test.raw.class$Class), positive = "1")
  
  score <- (2 * precision * recall) / (precision + recall)
  
  cat("XGB Test: (F1 score, Precision, Recall):", score, precision, recall,"\n")
  
  #saveRDS(xgb_mdl, "C:/Users/Mark/Documents/creditcard/xgb_mdl_tomek_smote.rds")
  
  Predictions <- cbind(Predictions, i = as.integer(test_xgb_yhat))
  
  colnames(Predictions)[i+1]=paste0("smote_pred_",i,sep="")
  
  Predictions[[i+1]][Predictions[[i+1]]==1] <- 0
  
  Predictions[[i+1]][Predictions[[i+1]]==2] <- 1
  
  #Predictions[[i+1]][Predictions[[i+1]]==2] <- as.numeric(score_train)
  
  train.raw.missed <- train.raw.origional[ which(train.raw.origional$Class!=train_xgb_yhat), ]
  
  train.raw.missed$Class <- as.factor(ifelse(train.raw.missed$Class == 0,'Good', 'Bad'))
  
  train.raw <- rbind(train.raw, train.raw.missed)
  
  #If the recall and precision scores rach 1 then the process stops early. 
  #Otherwise it continues to add the incorrectly classified training transactions. 
  
  if(recall==1 & precision==1){
    break
  }
  
}

write.csv(train.raw, "C:/Users/Mark/Documents/creditcard/train.raw.subset.csv", row.names=FALSE)

confusionMatrix(as.factor(train_xgb_yhat),  as.factor(train.raw.origional[,32]), mode = "prec_recall",positive = "1")

Predictions <- transform(Predictions, sum=rowSums(Predictions[,-1]))

Final_Predictions <- data.frame(prediction_id = test.raw$id, prediction = ifelse(Predictions$sum >= length(Predictions[,c(-1,-length(Predictions))])/2, "1", "0"))

write.csv(Final_Predictions, "C:/Users/Mark/Documents/creditcard/smote_pred/Final_Predictions.csv", row.names=FALSE)

end.time <- Sys.time()
time.taken <- end.time - start.time
time.taken

library(caret)

Final_Predictions <- read.csv("C:/Users/Mark/Documents/creditcard/smote_pred/Final_Predictions.csv",stringsAsFactors = FALSE)

test.raw <- read.csv("C:/Users/Mark/Documents/creditcard/test.csv",stringsAsFactors = FALSE)

test.raw <- test.raw[order(test.raw$id),] 

Final_Predictions <- Final_Predictions[order(Final_Predictions$prediction_id),]

confusionMatrix(as.factor(Final_Predictions$prediction),  as.factor(test.raw$Class), mode = "prec_recall",positive = "1")
