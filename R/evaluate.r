# Evaluation functions that take blimfit-objects and perform operations on them
# Functions: Summary, Bayes Factor, Convergence Plots, Autocorrelation Plots

# Erik-Jan van Kesteren


# Summary -----------------------------------------------------------------

summary.blimfit <- function(x,...){
  print(x$summary)
}


# DIC ---------------------------------------------------------------------

DIC <- function(blimfit){
  
  # Check if object has class blimfit
  if (class(blimfit) != "blimfit") stop("Please enter a blimfit object!")
  
  # Remove unnecessary information from the posterior distributions (the
  # R-squared column)
  trace <- blimfit$trace[,-c(ncol(blimfit$trace))]
  
  # loglikelihood under average of parameter estimates
  Dhat <- -2*sum(log(dnorm(blimfit$y,
                           blimfit$X%*%colMeans(trace[,-1]),
                           mean(trace[,1]))))
  
  #  Average loglikelihood of model for each sample
  Dbar <- -2*mean(apply(trace,1,
                        function(x)sum(log(dnorm(blimfit$y,
                                                 blimfit$X%*%x[-1],
                                                 x[1])))))
  
  DIC <- Dhat + 2 * (Dbar - Dhat)
  
  return(DIC)
}



# Bayes Factor ------------------------------------------------------------

lmml <- function(blimfit){
  
  # Laplace - Metropolis Marginal Likelihood using median approximation, from
  # Markov Chain Monte Carlo in Practice by Gilks, Richardson & Spiegelhalter
  # Page 171 & Appendix
  
  # Check if object has class blimfit
  if (class(blimfit) != "blimfit") stop("Please enter a blimfit object!")
  
  # Create log(P(Data | theta))
  llik <- function(theta,X,y){
    sum(log(dnorm(y,X%*%theta[-1],theta[1])))
  }
  
  # Create log(P(theta | Model)) from blimfit priors
  count <- 0
  h <- c("","")
  for (i in strsplit(blimfit$priors, "(", fixed = T)){
    count <- count+1
    if (count == 1){
      h[count]<- paste(append(i, paste("(1/theta[",count,"],",sep = ""), 
                              after = 1), collapse = "")
    } else {
      h[count]<- paste(append(i, paste("(theta[",count,"],",sep = ""), 
                              after = 1), collapse = "")
    }
  }
  lpriorstring <- paste(paste("log(",h,")", sep = ""),collapse = " + ")
  
  lprior <- function(theta)eval(parse(text = lpriorstring))
  
  
  
  # get the medians (computationally cheap alternative to multivariate mode)
  medians <- apply(blimfit$trace[,-ncol(blimfit$trace)],2,median) 
  
  # trace covmat is an unbiased estimate of the inverse hessian
  covmat <- cov(blimfit$trace[,-ncol(blimfit$trace)])
  logdet <- log(det(covmat))
  
  hmax <- llik(medians,blimfit$X,blimfit$y)+lprior(medians)
  
  # return the log of the estimated marginal likelihood
  return(unname(hmax+0.5*length(medians)*log(2*pi)+0.5*logdet))
  
}


BF <- function(blimfit1, blimfit2, bootstrap = F, plot = F){
  
  # Function to calculate the Bayes Factor of two (nested) models
  # Not much more than a wrapper around the lmml function!
  # use bootstrap to see if you need more iterations for accurate estimation
  # of the bayes factor
  
  # Check if object has class blimfit
  if (class(blimfit1) != "blimfit" ||
      class(blimfit2) != "blimfit") stop("Please enter a blimfit object!")
  
  if (bootstrap == F){
    
    # Calculate bayes factor. remember: lmml returns log marginal likelihood!
    BF <- exp(lmml(blimfit1)-lmml(blimfit2))
    names(BF) <- paste("Bayes Factor ",
                       as.list(sys.call())[[2]],"/",
                       as.list(sys.call())[[3]],sep = "")
    
  } else {
    
    cat("Warning! Bootstrap Bayes Factor can take a while. \n")
    
    # Initialise output vector
    BFs <- numeric(1000)
    
    # Start bootstrap procedure
    for (i in 1:1000){
      h1 <- blimfit1
      h1$trace <- h1$trace[sample(nrow(h1$trace),replace = T),]
      h2 <- blimfit2
      h2$trace <- h2$trace[sample(nrow(h2$trace),replace = T),]
      BFs[i]<-exp(lmml(h1)-lmml(h2))
    }
    
    # Output estimate and 95% interval
    BF <- c(mean(BFs),quantile(BFs, probs = c(0.025, 0.975)))
    names(BF)[1] <- paste("BayesFactor ",
                          as.list(sys.call())[[2]],"/",
                          as.list(sys.call())[[3]],sep = "")
    
    # Plot the bootstrap distribution
    if (plot == T){
      hist(BFs, breaks = "FD", col = "light green", border = "light green",
           main = "Bootstrap Distribution of Bayes Factor", 
           xlab = "Bayes Factor")
    }
  }
  return(BF)
}


ICBF <- function(blimfit, model = "par[1] < par[2]", complement = F){
  
  # Bayes Factor for Informative Hypotheses (e.g. comparing means)
   
  # A short introduction into Bayesian evaluation of informative hypotheses as
  # an alternative to exploratory comparisons of multiple group means
  # Beland, Klugkist, Raiche & Magis (2012)
  
  # Check if object has class blimfit
  if (class(blimfit) != "blimfit") stop("Please enter a blimfit object!")
  
  # Remove unnecessary information from the posterior distributions (the
  # variance and R-squared columns)
  trace <- blimfit$trace[,-c(1,ncol(blimfit$trace))]
  priors <- blimfit$priors[-1]
  
  # Create evaluable expressions for priors from which we can sample
  p <- lapply(lapply(lapply(strsplit(priors, "(", fixed = T),
                            function(x)append(x,"(nrow(trace),", after = 1)),
                     function(x)paste(x,collapse="")),
              function(x)paste("r",substr(x,2,nchar(x)), sep = ""))
  
  # Create a trace of prior information NOTE that with few iterations this is
  # just a rough approximation as this random sequence is NOT taken from the 
  # Markov chain directly. Asymptotically, this becomes more precise.
  prior <- matrix(unlist(lapply(p,function(x)eval(parse(text=x)))),
                  nrow = nrow(trace))
  

  # Evaluate fit of the hypothesis
  fa <- mean(apply(trace, 1, function(par) eval(parse(text=model))))
  
  # Evaluate complexity of the hypothesis
  ca <- mean(apply(prior, 1, function(par) eval(parse(text=model))))
  
  # We can evaluate the BF against unconstrained hypothesis or against its
  # complement.
  if (complement == F){
    BFau <- fa/ca 
    # Bayes factor against the unconstrained hypothesis
    return(c(fit = fa, complexity = ca, BFau = BFau))
  } else {
    fc <- mean(apply(trace, 1, function(par){
      eval(parse(text=paste("!(",model,")", sep = "")))
    }))
    cc <- mean(apply(prior, 1, function(par){
      eval(parse(text=paste("!(",model,")", sep = "")))
    }))
    BFac <- (fa/ca)/(fc/cc)
    return(c(fit_a = fa, compl_a = ca, fit_c = fc, compl_c = cc, BFac = BFac))
  }
  
}


# Posterior Predictive Check ----------------------------------------------

PPC <- function(blimfit, fast = TRUE, type = "norm"){
  
  # POSSIBLE TYPES
  # norm : a PPC for normality of residuals using ks.test
  # dw : a PPC for autocorrelation of residuals using durbin-watson statistic
  # more types are very easy to add. just create a function of the data or of 
  # the residuals that returns a discrepancy measure and add it in the apply
  # of ObsD and RepD. That adds a row to each of these, which can then be 
  # checked.
  
  # Check if object has class blimfit
  if (class(blimfit) != "blimfit") stop("Please enter a blimfit object!")
  
  # Remove unnecessary information from the posterior distributions (the
  # R-squared column)
  if (fast == F){
    trace <- blimfit$trace[,-c(ncol(blimfit$trace))]
    cat("Precise PPP calculation. This might take a while! \n\n")
  } else {
    trace <- blimfit$trace[sample(nrow(blimfit$trace),1000),
                           -c(ncol(blimfit$trace))]
    cat("Fast PPP calculation. Only 1000 iterations evaluated.
Turn off the option 'fast' to perform a precise PPP calculation. \n\n")
  }
  
  
  
  # Calculate the observed discrepancy measure for each row of the trace
  obsD <- apply(trace[,-1],1,function(b){
    # Calculate discrepancy measure
    resid <- blimfit$y-blimfit$X%*%b
    
    # For Durbin-Watson autocorrelation test
    auto <- resid[-1]-resid[-length(resid)]
    DW <- (t(auto)%*%auto)/(t(resid)%*%resid)
    Ddw <- abs(DW-2)
    
    # For normality of residuals: ks.test
    Dnm <- suppressWarnings(ks.test(resid,pnorm)$statistic)
    
    return(c(Ddw,Dnm))
    })
  
  # Calculate the replicated discrepancy measure for each row of the trace
  repD <- apply(trace,1,function(trace){
    # Assign proper parameters
    var <- trace[1]
    b <- trace[-1]
    # Generate data under model
    y <- apply(blimfit$X%*%b,1,function(mean){rnorm(1,mean,sqrt(var))}) 
    
    # Calculate discrepancy measure
    resid <- y-blimfit$X%*%b
    
    # For Durbin-Watson Autocorrelation test
    auto <- resid[-1]-resid[-length(resid)]
    DW <- (t(auto)%*%auto)/(t(resid)%*%resid)
    Ddw <- abs(DW-2)
    
    # For normality of residual: ks.test
    Dnm <- suppressWarnings(ks.test(resid,pnorm)$statistic)
    
    return(c(Ddw,Dnm))
  })
  
  # PPP is how often the observed D is smaller than replicated D
  PPPDW <- mean(obsD[1,] < repD[1,])
  PPPNM <- mean(obsD[2,] < repD[2,])
  
  out <- list()
  if (any(toupper(type)=="DW")) out$ResidualAutocorrelation <- PPPDW
  if (any(toupper(type)=="NORM")) out$ResidualNormality <- PPPNM
  
  return(out)

}


# Convergence Plots -------------------------------------------------------


cplots <- function(blimfit, params = NULL, limit = TRUE){
  
  # Check if object has class blimfit
  if (class(blimfit) != "blimfit") stop("Please enter a blimfit object!")
  
  # Get the trace
  trace <- blimfit$trace
  
  if (limit == T && nrow(trace)>10000) {
    thin <- round(nrow(trace)/10000)
    select <- (1:nrow(trace))[seq(thin,nrow(trace), length.out = 10000)]
    cat("Trace has",nrow(trace),"samples. Only 10000 shown.
Turn off the option 'limit' to show all observations (slow!).")
  } else {
    select <- 1:nrow(trace)
  }
  
  
  # If parameters not given assume all params.
  if (!is.numeric(params)){
    params <- 1:ncol(trace)
  }
  
  # Store and set margins
  margins <- par("mar")
  par(mar = c(2.1,4.1,0.6,1.1))
  
  # Store and set columns & rows
  if (length(params) < 5){
    par(mfrow = c(length(params),2))
  } else {
    par(mfrow = c(4,2))
  }
  
  for (i in params){
    plot(select, trace[select,i], type = "l", col = "blue", main = "", 
         xlab = "", ylab = colnames(trace)[i])
    hist(trace[select,i], breaks = "FD", xlab = "", ylab = "frequency", main = "", 
         col = "dark green", border = "dark green")
    abline(v = mean(trace[,i]), col = "white")
  }
  
  par(mfrow = c(1,1), mar = margins)
  
}


# Autocorrelation Plots ---------------------------------------------------

aplots <- function(blimfit, params = NULL){
  
  # Check if object has class blimfit
  if (class(blimfit) != "blimfit") stop("Please enter a blimfit object!")
  
  # MH warning message
  if (blimfit$algorithm == "R based Metropolis-Hastings Sampling Regression"){
    cat("Check that acceptance rates are between 0.15 and 0.5 in console at blim 
output.",
        "\n")
  }
  
  # Pick up trace for the column names
  trace <- blimfit$trace[1:2,]
  
  # Pick up autocorrelation
  auto <- blimfit$auto
  
  
  # If parameters not given assume all params.
  if (!is.numeric(params)){
    params <- 1:ncol(trace)
  }
  
  # Store and set margins
  margins <- par("mar")
  par(mar = c(2.1,4.1,0.6,1.1))
  
  # Store and set columns & rows
  if (length(params) < 5){
    par(mfrow = c(length(params),1))
  } else {
    par(mfrow = c(4,1))
  }
  
  for (i in params){
    plot(auto[i,], type = "h", col = "blue", main = "", 
         xlab = "", ylab = colnames(trace)[i], lwd = 3, ylim = c(0,1))
  }
  
  par(mfrow = c(1,1), mar = margins)
  
}
