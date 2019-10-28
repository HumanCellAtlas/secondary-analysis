# This Rscript is designed to run in Rstudio to get a better result
# You must change the code in main() function to generate new visualizations

library('ggplot2')
library('rjson')
library('grid')
library('gridExtra')

read_rtts <- function(JsonData) {
  return(JsonData$data$rtt)
}

prepare_index <- function(rtt) {
  return(c(1:length(rtt)))
}

prepare_dataframe <- function(rtt, index) {
  return(data.frame(index, rtt))
}

dotplot_JSON <- function(JsonData) {
  rtt <- read_rtts(JsonData)
  index <- prepare_index(rtt)
  dataframe <- prepare_dataframe(rtt, index)
  
  graph <- ggplot() +
    aes(dataframe$index, dataframe$rtt) +
    geom_point() +
    geom_hline(yintercept = mean(rtt), color = "red") +
    geom_text(aes(
      0,
      mean(rtt),
      label = paste('AvgRTT:', mean(rtt)),
      vjust = -6,
      hjust = 0
    ), color = "red") +
    labs(x = "Notifications", y = "RTT-Round Trip Time (secs)")
  
  marginal_graph <-
    graph + scale_y_continuous(limits = c(min(dataframe$rtt), max(dataframe$rtt))) + geom_rug(col =
                                                                                                rgb(.5, 0, 0, alpha = .2), sides = 'l')
  return(marginal_graph)
}

check_metadata <- function(data1, data2) {
  if ((data1$metadata$lira == data2$metadata$lira) &&
      (data1$metadata$environment == data2$metadata$environment) &&
      (data1$metadata$mode == data2$metadata$mode) &&
      (data1$metadata$cromwell == data2$metadata$cromwell) &&
      (data1$metadata$caching == data2$metadata$caching)) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}

group_two_graphs <- function(data1, data2, g1, g2) {
  if (check_metadata(data1, data2)) {
    grouped <- grid.arrange(
      g1,
      g2,
      nrow = 2,
      top = paste(
        "Lira Load Testing Metrics -",
        "Lira-",
        data1$metadata$lira,
        "Server-",
        data1$metadata$environment,
        "Mode-",
        data1$metadata$mode,
        "Cromwell-",
        data1$metadata$cromwell,
        "lira-caching-",
        data1$metadata$caching
      )
    )
    return(grouped)
  } else {
    stop("Cannot group two result graphs under different experiments.")
  }
}

group_three_graphs <- function(data1, data2, data3, g1, g2, g3) {
  if (check_metadata(data1, data2) && check_metadata(data2, data3)) {
    grouped <- grid.arrange(
      g1,
      g2,
      g3,
      nrow = 3,
      top = paste(
        "Lira Load Testing Metrics -",
        "Lira-",
        data1$metadata$lira,
        "Server-",
        data1$metadata$environment,
        "Mode-",
        data1$metadata$mode,
        "Cromwell-",
        data1$metadata$cromwell,
        "lira-caching-",
        data1$metadata$caching
      )
    )
    return(grouped)
  } else {
    stop("Cannot group three result graphs under different experiments.")
  }
}

main <- function() {
  # Set Working Directory
  setwd("./data/results/")
  
  # Load JSONData
  data1 <- fromJSON(file = 'load_test_result_20180408-225213.json')
  data2 <- fromJSON(file = 'load_test_result_20180408-225619.json')
  
  data3 <- fromJSON(file = 'load_test_result_20180408-234606.json')
  data4 <- fromJSON(file = 'load_test_result_20180409-012513.json')
  
  data5 <- fromJSON(file = 'load_test_result_20180409-224547.json')
  data6 <- fromJSON(file = 'load_test_result_20180409-231022.json')
  data7 <- fromJSON(file = 'load_test_result_20180409-234726.json')
  
  # Draw Graphs
  g1 <- dotplot_JSON(data1)
  g2 <- dotplot_JSON(data2)
  
  # Draw Grouped Graphs
  G1 <- group_two_graphs(data1, data2, g1, g2)
  G1
  
  g3 <- dotplot_JSON(data3)
  g4 <- dotplot_JSON(data4)
  
  G2 <- group_two_graphs(data3, data4, g3, g4)
  G2
  
  g5 <- dotplot_JSON(data5)
  g6 <- dotplot_JSON(data6)
  g7 <- dotplot_JSON(data7)
  G3 <- group_three_graphs(data5, data6, data7, g5, g6, g7)
  G3
}

main()
