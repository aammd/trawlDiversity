// ===============
// = Conventions =
// ===============
// Data Structures:
  // Arrays: last index is fastest (most specific, smallest)
  // Matrices: first index (row) is fastest
// Notation:
  // Scalar capital letters are the maximum value for their lowercase counterpart (t = 1, 2, ..., T)
  // Greek letters are parameters
  // State variables and covariates are capital Roman letters (X, Z, Y, U)

// =============
// = Functions =
// =============
functions {
  
	// these functions were part of my failed attempt to vectorize
	
  // ---- log probability functions ----
  
  // lp for species that are observed
  vector lp_obs(int[] x, int K,  vector lil_lp, row_vector logit_theta) {
    return lil_lp + binomial_logit_log(x, K, logit_theta);
  }
  
  // lp for species that aren't observed, but known to exist
  real lp_unobs(int K, vector lil_lp, row_vector logit_theta, vector l1mil_lp) {
    int D;
    D <- cols(logit_theta);
    return log_sum_exp(log_sum_exp(lp_obs(rep_array(0, D), K, lil_lp, logit_theta)), log_sum_exp(l1mil_lp));
  }
  
  // lp that works as either lp_obs or lp_unobs, depending on isUnobs values
  real lp_exists(int[] x, int K, vector lil_lp, row_vector logit_theta, vector isUnobs, vector l1mil_lp) {
    return log_sum_exp(log_sum_exp(lp_obs(x, K, lil_lp, logit_theta)), log_sum_exp(l1mil_lp .* isUnobs));
  }
  
  // lp for species that were never observed
  real lp_never_obs(int K, vector lil_lp, row_vector logit_theta, real Omega, vector l1mil_lp) {
    real lp_unavailable;
    real lp_available;
    int D;
    D <- cols(logit_theta);
    lp_unavailable <- bernoulli_log(0, Omega)*D;
    lp_available <- log_sum_exp(bernoulli_log(1, Omega)*D, lp_unobs(K, lil_lp, logit_theta, l1mil_lp));
    return log_sum_exp(lp_unavailable, lp_available);
  }
  
  
}


// ========
// = Data =
// ========
data {
    int<lower=1> nT; // number of years
    int<lower=1> Kmax; // max samples in a site-year
    int<lower=1> Jmax; // number of sites
    int<lower=0, upper=Jmax> nJ[nT]; // number of sites in each year
    int<lower=0, upper=Kmax> nK[nT,Jmax]; // number of samples (replicates/ hauls)
    int nU; // number of Covariates for psi (presence)
    int nV; // number of Covariates for theta (detection)
    
    int N; // total number of observed species (anywhere, ever)
    int<lower=1> nS; // size of super population, includes unknown species
    vector[nS] isUnobs[nT,Jmax]; // was a species unobserved (across all K) each site-year?
    // int isObs[nT,Jmax,nS]; // binary {0,1} version of X, opposite of isUnobs
    
    int nU_c; // number of presence covariates that are constants
    int nV_c; // number of detection covariates that are contants
    int nU_rv; // number of presence covariates that are random variables (params)
    int nV_rv; // number of detection covariates that are random variables (params)
    matrix[Jmax, nU_c] U_c[nT]; // psi (presence) covariates that are consants
    matrix[Jmax, nV_c] V_c[nT]; // theta (detection) covariates that are consants
    matrix[Jmax,nU_rv] U_mu[nT]; // sample mean for psi covariates (U)
    matrix[Jmax,nU_rv] U_sd[nT]; // sample sd for U
    matrix[Jmax,nV_rv] V_mu[nT]; // sample mean for theta covariates (V)
    matrix[Jmax,nV_rv] V_sd[nT]; // sample sd for V
    
    int X[nT,Jmax,nS]; // species abundances
}


// ====================
// = Transformed Data =
// ====================
transformed data {
	int<lower=0, upper=(Jmax*nT)> nJ_sum;
	
	nJ_sum <- sum(nJ);
}


// ==============
// = Parameters =
// ==============
parameters { 
  real<lower=0, upper=1> Omega;
  
  vector[nU] alpha_mu; // hyperparameter mean
  vector<lower=0>[nU] alpha_sd; // hyperparameter sd
  matrix[nU,nS] alpha_raw; // non-centered presence coefficient
  
  vector[nV] beta_mu; // hyperparameter mean
  vector<lower=0>[nV] beta_sd; // hyperparameter sd
  matrix[nV,nS] beta_raw; // detection coefficient
  
  matrix[Jmax,nU_rv] U_raw[nT]; // predictors for psi, not including intercept
  matrix[Jmax,nV_rv] V_raw[nT]; // predictors for theta, not including intercept
  
}


// ==========================
// = Transformed Parameters =
// ==========================
transformed parameters {

  // ---- declare ----
  matrix[nU,nS] alpha; // presence coefficient
  matrix[nV,nS] beta; // detection coefficient

  matrix[Jmax, nU] U[nT]; // presence covariates
  matrix[Jmax, nV] V[nT]; // detection covariates
	
	matrix[Jmax, nS] logit_psi[nT]; // logit presence probability
	matrix[Jmax, nS] logit_theta[nT]; // logit detection probability
  
  // real Omega; // average availability
  
  
  // ---- define ---- 
  // coefficients
  for (u in 1:nU) {
    alpha[u] <- alpha_mu[u] + alpha_sd[u]*alpha_raw[u];
  }
  for (v in 1:nV) {
    beta[v] <- beta_mu[v] + beta_sd[v]*beta_raw[v];
  }
  
  // covariates
  for (t in 1:nT) { 
    matrix[Jmax, nU_rv] tU; // annual covariates, aside from intercept
    matrix[Jmax, nV_rv] tV;
    
    tU <- U_mu[t] + U_raw[t] .* U_sd[t]; // center
    tV <- V_mu[t] + V_raw[t] .* V_sd[t];
    
    U[t] <- append_col(U_c[t], tU); // add covaraites that are constants
    V[t] <- append_col(V_c[t], tV); // add constant detection covs
  }
	
	// psi and theta
	for (t in 1:nT) {
		logit_psi[t] <- U[t]*alpha;
		logit_theta[t] <- V[t]*beta;
	}
	 
}


// =========
// = Model =
// =========
model {
  
  // ---- Priors for Hyperparameters ----
  alpha_mu ~ cauchy(0, 1);
  alpha_sd ~ cauchy(0, 2);
  beta_mu ~ cauchy(0, 1);
  beta_sd ~ cauchy(0, 2);

  
  
  // ---- Priors for Parameters ----
  Omega ~ beta(2,2);
  
  for (u in 1:nU) {
    alpha_raw[u] ~ normal(0, 1); // implies alpha ~ normal(alpha_mu, alpha_sd)
  }
  for (v in 1:nV) {
    beta_raw[v] ~ normal(0, 1); // implies beta ~ normal(beta_mu, beta_sd)
  }
  
  for (t in 1:nT) {
    for (j in 1:Jmax) { 
      U_raw[t][j] ~ normal(0, 1); // implies U ~ normal(U_mu, U_sd)
      V_raw[t][j] ~ normal(0, 1); // implies V ~ normal(V_mu, V_sd)
    }
  }
  
  
  // ---- Begin Looping down to Point Observations ----
	increment_log_prob(bernoulli_log(1, Omega) * N); // observed, so available
	for (n in 1:N) {
		// 1 ~ bernoulli(Omega);
		for (t in 1:nT) {
			for (j in 1:Jmax) {
				if (nK[t,j] > 0) {
					if ( X[t,j,n] > 0) {
						increment_log_prob(log_inv_logit(logit_psi[t][j,n]) + binomial_logit_log(X[t,j,n], nK[t,j], logit_theta[t][j,n]));
					} else {
						increment_log_prob(log_sum_exp(log_inv_logit(logit_psi[t][j,n]) + binomial_logit_log(0, nK[t,j], logit_theta[t][j,n]), log1m_inv_logit(logit_psi[t][j,n])));
					}
				}
			}
		}
	}
	
	for (s in (N+1):nS) {
		real lp_unavailable; // unavail part of never obs prob
		real lp_available; // available part of never obs prob
		vector[nJ_sum] lp_available_pt1; // stores 'present but undetected' part of 'never obs but avail' term
		int pos;
		
		pos <- 1;
		
		for (t in 1:nT) {
			for (j in 1:Jmax) {
				if (nK[t,j] > 0) {
					lp_available_pt1[pos] <- log_sum_exp(log_inv_logit(logit_psi[t][j,s]) + binomial_logit_log(0, nK[t,j], logit_theta[t][j,s]), log1m_inv_logit(logit_psi[t][j,s]));
					pos <- pos + 1;
				}
				
			}
		}
		lp_unavailable <- bernoulli_log(0, Omega);
		lp_available <- bernoulli_log(1, Omega) + sum(lp_available_pt1);
		increment_log_prob(log_sum_exp(lp_unavailable, lp_available));
	}
	
	
//   for (t in 1:nT) { // loop through years
//
//     if(nJ[t]){ // statement only necessary if using failed approach for vectorization
//
// 			// failed attempt to vectorize
//       // matrix[nJ[t],nS] logit_psi; // presence probability
//       // matrix[nJ[t],nS] logit_theta; // detection probability
//       //
//       // logit_psi <- block(U[t], 1, 1, nJ[t], nU) * alpha; // block matrix algebra for speed
//       // logit_theta <- block(V[t], 1, 1, nJ[t], nV) * beta; // block matrix algebra for speed
//
//       for (j in 1:nJ[t]) { // sites
//
//
//         if(nK[t,j]){ // if samples in site
//
//           row_vector[nS] t_logit_psi; // presence
//           row_vector[nS] t_logit_theta; // detection
//           vector[nS] lil_lp; // log_inv_logit(logit_psi)
//           vector[nS] l1mil_lp; // log1m_inv_logit(logit_psi)
//
//           t_logit_psi <- sub_row(logit_psi[t], j, 1, nS);
//           t_logit_theta <- sub_row(logit_theta[t], j, 1, nS);
//
//           for (s in 1:nS){
//             l1mil_lp[s] <- log1m_inv_logit(t_logit_psi[s]);
//             lil_lp[s] <- log_inv_logit(t_logit_psi[s]);
//           }
//
// 					// failed attempt to vectorize
//           // species that have been observed at some point
//           // print("t=",t, ", j=", j, ", lp for lp_exists before =", get_lp());
//           // increment_log_prob(lp_exists(
// //             segment(X[t,j], 1, N), // x
// //             nK[t,j], // K
// //             segment(lil_lp, 1, N), // vector lil_lp
// //             segment(t_logit_theta, 1, N), // row_vector logit_theta
// //             segment(isUnobs[t,j], 1, N), // vector isUnobs
// //             segment(l1mil_lp, 1, N) // vector l1mil_lp
// //           ));
// 					for (n in 1:N) {
// 						if ( X[t,j,n] > 0) {
// 							increment_log_prob(lil_lp[n] + binomial_logit_log(X[t,j,n], nK[t,j], t_logit_theta[n]));
// 						} else {
// 							increment_log_prob(log_sum_exp(lil_lp[n] + binomial_logit_log(0, nK[t,j], t_logit_theta[n]), l1mil_lp[n]));
// 						}
// 					}
//
// 					// failed attempt to vectorize
//           // species that have never been observed
//           // increment_log_prob(lp_never_obs(
//           //   nK[t,j], // int[] K
//           //   segment(lil_lp, N+1, nS-N), // vector lil_lp
//           //   segment(t_logit_theta, N+1, nS-N), // row_vector logit_theta
//           //   Omega, // real Omega
//           //   segment(l1mil_lp, N+1, nS-N) // vector l1mil_lp
//           // ));
// 					for (s in (N+1):nS) {
// 						real lp_unavailable;
// 						real lp_available;
// 						lp_unavailable <- bernoulli_log(0, Omega);
// 						lp_available <- bernoulli_log(1, Omega) + log_sum_exp(lil_lp[s] + binomial_logit_log(0, nK[t,j], t_logit_theta[s]), l1mil_lp[s]);
// 						increment_log_prob(log_sum_exp(lp_unavailable, lp_available));
// 						// increment_log_prob(log_sum_exp(lil_lp[s] + binomial_logit_log(0, nK[t,j], t_logit_theta[s]), l1mil_lp[s]));
// 					}
//
//         } // if nK
//       } // end site loop
//     } // if nJ
//   } // end year loop
  
} // end model


// ========================
// = Generated Quantities =
// ========================
// generated quantities {
//   matrix[Jmax,nS] logit_psi[nT]; // presence probability
//   matrix[Jmax,nS] logit_theta[nT]; // detection probability
//   for (t in 1:nT) { // loop through years
//       logit_psi[t] <- U[t] * alpha; // block matrix algebra for speed
// 			logit_theta[t] <- V[t] * beta; // block matrix algebra for speed
//   } // end year loop
// }

