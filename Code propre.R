library(Rhabit)
library(viridis)
library(ggplot2)
library(gridExtra)
library(abind)
library(dplyr)
library(RandomFields)
library(RandomFieldsUtils)
library(markovchain)
library(tidyverse)
library(RColorBrewer)
library(MASS)
library(mvtnorm)
library(psych)
library(FactoMineR)



################################################################################
#                                                                              #
#                         Les différentes fonctions                            #
#                                                                              #
################################################################################       

################################################################################
###                       Quelques fonctions pratiques                       ###                               
################################################################################
# Fonction permettant de rendre stochastique une matrice devant l'être.
# Utilisée dans l'EM.
format_mat = function(A){
  l = ncol(A)
  for (i in 1:l){
    A[i,] = A[i,]/(sum(A[i,]))
  }
  return(A)
}

increments = function(liste){
# Ca n'est pas très efficace de faire grossir un vecteur au fur et à mesure, 
# ca fait bcp d'allocation memoire inutile et de copie dan sla zone mémoire
# n <-  length(liste) - 1
# l <-  numeric(length = n)
# for (i in 1:(length(liste)-1)){
#   l[i] <- liste[i+1] - liste[i]
# }
# Une autre option encore plus efficace
# l <- diff(liste)  
  
    l = c()
  for (i in 1:(length(liste)-1)){
    l = c(l,liste[i+1] - liste[i])
  }
  return(l)
}

matrix_to_list = function(mat){
# meme remarque que dans la fonction précédente, autant que possible quand tu connais la taille
#   d'un objet il faut l'allouer des le début
      l = list()
  N = ncol(mat)
  for (i in 1:N){
    l[[i]] = c(mat[,i])
  }
  return(l)
}


################################################################################
###                Générateur de la chaîne des états cachés                  ###                               
################################################################################
# Fonction permettant de générer une chaîne de Markov. Elle est généralisée de 
# façon à ce qu'on n'ait pas à donner la suite de "noms" des états.
# Paramètres : 
#           - A, la matrice de transition de la chaîne au format matrix. 
#           - T, le nombre souhaité d'itérations de la chaîne.
#
# Retourne une suite numérique des états successifs.

CM_generateur = function(A, T){
  
  # On commence par générer la suite "states".
  K = dim(A)[1]
  states = c()
  for (i in 1:K){states = c(states, as.character(i))}
# Autre option 
# as.character(1:K)
  # On génère maintenant la chaîne de Markov. 
  CM<-new("markovchain", states = states,
          transitionMatrix = A, 
          name = "Q")
  return(as.numeric(markovchainSequence(T,CM)))
}





################################################################################
###                        Création des paramètres                           ###                               
################################################################################
## peux tu indiquer le role des arguments del afonction 
## K : nb états dans la chaine
## J nombre de covariables

BETA = function(K, J){
  n = K*J
  liste = runif(n,-5,5)
  return(matrix(liste, ncol = K, nrow = J))
}
Nu = function(BETA, delta, vit) { 
  # Delta n'intervient pas danss le calcul de nu '
  # nu = gamma^2 Beta, j'imagine que le gamma du papier est vit ici 
  # # Les constantes utiles.
  dim = dim(BETA)
  J = dim[1]
  K = dim[2]
  
  # Création de la matrice.
  L = matrix(1, ncol = K, nrow = J)
  
  # Remplissage.
  for (k in 1:K){
    for (j in 1:J){
      L[j,k] = (BETA[j,k]*sqrt(delta)*vit**2)
    }
  }
  return(L)
}

BetaToNu = function(Beta, Vit){
  # Fonction qui prend en paramètre les betas et les gamma2 selon les etats et qui 
  # doit renvoyer la matrice theta correspondante.
  # Question est que vit = gamma ou gamma^2
  C = c()
  K = length(Vit)
  J = length(Beta[[1]])
  
  # Dans R on peut faire un produit terme à terme
  # C <- matrix(NA, ncol = ncol(Beta), nrow = nrow(Beta))
  # for (k in 1:K){
  # C[,k] <- Beta[,k]*Vit[k]  ## ou Vit^2 à clarifier
  # }
  # 
  # ou meme encore plus compact mais moins lisible
  # C <-  sweep(beta, 2, STATS = vit, FUN =  "*")
  # Rmq C désigne aussi les covariables autant appelé ca Nu dans la fonction aussi
  
  for (i in 1:K){
    C = c(C, Beta[[i]] * Vit[i])
  }
  return(matrix(C, ncol = K, nrow = J))
}


################################################################################
###                     Probabilités des apparitions                         ###                               
################################################################################
# Fonction calculant la probabilité des émissions, c'est à dire la probabilité 
# de chaque "partie" du déplacement de l'animal. Il prend en compte la 
# dimension 1 et 2.

# Paramètres :
#         - obs, le data.frame contenant les informations sur le déplacement.
#         - C, la matrice des covariables environnementales.
## C est utilisé juste au desuus pouyr Beta * Vit
#         - theta, le paramètre de lien.
#         - Delta, la suite des pas de temps.
#         - vit, la "vitesse" du processus aléatoire.
#         - dimension, la dimension considérée, elle est de base égale à 2. 
#
# Retourne un dataframe avec deux composantes :
#         - B, la matrice des probabilités des déplacements, T lignes, K 
#           colonnes.
#
# Remarques :
#         - Seules les dimensions 1 et 2 sont prises en compte ici.


proba_emission = function(obs, C, theta, Delta, Vits, dimension = 2){
  
  nbr_obs = length(obs$Z1) - 1  # On enleve 1 pour ne pas prendre le NA.
  K = dim(theta)[2]
  
  # Création de la matrice.
  B = matrix(0, ncol = K, nrow = nbr_obs)
  if (dimension == 2){
    # On implémente Z sous un format pratique pour la suite.
    Z = cbind(obs$Z1[1:nbr_obs], obs$Z2[1:nbr_obs])
    
    # Remplissage de la matrice.
    for (t in 1:nbr_obs){
      C_tilde = matrix( c(C[t,],C[nbr_obs + t,]), nrow=2, byrow=TRUE)
      mu =  C_tilde %*% theta / sqrt(Delta[t]) 
      for (k in 1:K){B[t,k] = dmvnorm( Z[t,], mu[,k], Vits[k]**2 * diag(2))}
    }
  }
  else {
    # Remplissage de la matrice.
    for (t in 1:nbr_obs){
      for (k in 1:K){B[t,k] = dnorm(obs$Z[t],Delta[t]*(C[t,] %*% theta[,k]),vit)}
    }
  }
  return(B)
}
p = proba_emission(Obs, C, theta_initial, incr,  Vits = c(1,0.2), 
               dimension)

################################################################################
###                      Génération des observations                         ###                               
################################################################################

Obs_generateur = function(Q, theta, C, vit, delta, dimension = 2){
  nbr_obs = length(Q) - 2 
  
  if (dimension == 2){
    # On considère que l'animal part de l'origine.
    X1 = c(0)
    X2 = c(0)
    Z1 = c(0)
    Z2 = c(0)
    
    for (i in 2:nbr_obs) {
      # MU.
      C_tilde = matrix(c(C[i,],C[nbr_obs+i,]),nrow=2,byrow=TRUE) # Matrice C modifiée.
      mu = C_tilde%*%theta[,Q[i]]
      
      # Sigma.
      #Sigma = (vit**2) * delta[i-1]* diag(2) 
      Sigma = (vit**2) * diag(2) 
      
      # Calcul du déplacement.
      e = mvrnorm(1,  mu/sqrt(delta[i-1]), Sigma)
      #e = mvrnorm(1,  mu * delta[i-1], Sigma)
      if(abs(e[1]) > 4 ){ browser()}
      # Stockage des données.
      X1 = c(X1, X1[i-1] + e[1])
      X2 = c(X2, X2[i-1] + e[2])
      Z1 = c(Z1, e[1])
      Z2 = c(Z2, e[2])
    }
    return(data.frame('X1' = X1, 'X2' = X2, 'Z1' = Z1, 'Z2' = Z2))
  }
  
  else {
    # On considère que l'animal part de l'origine.
    X = c(0) # Départ déterministe en l'origine.
    Z = c(0)
    
    # Sigma. 
    Sigma = delta * vit**2
    
    for (i in 2:nbr_obs) {
      # Mu.
      mu = C[i,]%*%theta[,Q[i]]
      
      # Calcul du déplacement.
      e = rnorm(1, delta[i-1]*mu, Sigma[i-1])
      
      # Stockage des données.
      X = c(X, X[i-1] + e)
      Z = c(Z, e)
    }
    return(data.frame('X' = X, 'Z' = Z))
  }
}

Generation_observation = function(theta, Q, liste_cov, vit, tps, 
                                  loc0 = c(0,0)){
  K = dim(theta)[2]
  nbr_obs = length(Q)
  Obs <- matrix(NA, nbr_obs, 2)
  Obs[1,] = loc0
  for (t in (1:(nbr_obs-1))) {
    print(t)
    # On regarde l'état dans lequel on se trouve.
    etat = Q[t]
    print(etat)
    # On simule le déplacement.
    xy = simLangevinMM(matrix_to_list(theta)[[etat]], vit, c(tps[t],tps[t+1]),
                       loc0 = c(0,0), cov_list = liste_cov, keep_grad = FALSE)
    Obs[t,] = as.vector(as.numeric(xy[2,][,1:2])) # On ne prend que les coordonnées du déplacement.
    loc0 = as.vector(as.numeric(xy[2,][,1:2]))
  }
  return(Obs)}

Generation_observation2.0 = function(beta, Q, C, vit, time, loc0 = c(0,0),
                                     affichage = TRUE){
  K = dim(theta)[2]
  t = length(Q)
  print(t)
  Obs <- matrix(NA, t-1, 2)
  Obs[1,] = loc0
  for (t in 1:(t-1)) {
    xy = simLangevinMM(beta[[Q[t]]], vit, c(tps[t],tps[t+1]), c(0,0), liste_cov, keep_grad = FALSE)
    Obs[t,] = as.vector(as.numeric(xy[2,][,1:2])) # On ne prend que les coordonnées du déplacement.
    loc0 = as.vector(as.numeric(xy[2,][,1:2]))
  }
  
  # On s'occupe du format de retour. 
  
  # Les Z. 
  
  
  # Les X. 
  Observations = data.frame('X1' = Obs[,1], 'X2' = Obs[,2],
                            'Z1' = c(increments(Obs[,1]), NA), 
                            'Z2' = c(increments(Obs[,2]), NA))
  # if (affichage){
  #   Obs_affichage = Observations
  #   Obs_affichage$'etats' = as.factor(Q[1:t-1])
  #   
  #   ggplot(Obs_affichage, aes(X1, X2)) +
  #     geom_path()+
  #     geom_point(aes(colour = etats)) 
  # }
  
  return(Observations)}

Generation_observation3.0 = function(beta, Q, C, Vits, time, loc0 = c(0,0), 
                                     affichage = TRUE){
  K = dim(theta)[2]
  t = length(Q) 
  Obs <- matrix(NA, t, 2)
  Obs[1,] = loc0
  for (t in 2:(t)) {
    xy = simLangevinMM(beta[[Q[t]]], Vits[Q[t]], c(tps[t-1],tps[t]), c(0,0), liste_cov, keep_grad = FALSE)
    Obs[t,] = as.vector(as.numeric(xy[2,][,1:2])) # On ne prend que les coordonnées du déplacement.
    loc0 = as.vector(as.numeric(xy[2,][,1:2]))
  }
  
  # On s'occupe du format de retour. 
  
  # Les Z. 
  
  
  # Les X. 
  Observations = data.frame('X1' = Obs[,1], 'X2' = Obs[,2],
                            'Z1' = c(increments(Obs[,1]), NA), 
                            'Z2' = c(increments(Obs[,2]), NA))
  # if (affichage){
  #   Obs_affichage = Observations
  #   Obs_affichage$'etats' = as.factor(Q[1:t-1])
  #   
  #   ggplot(Obs_affichage, aes(X1, X2)) +
  #     geom_path()+
  #     geom_point(aes(colour = etats)) 
  # }
  
  return(Observations)}

#Obs = Generation_observation(theta, Q, liste_cov = liste_cov, vit, tps)


################################################################################
###                     Procédures forward et backward                       ###                               
################################################################################

forward_2.0 = function( A, B, PI){
  nbr_obs = dim(B)[1]
  K = dim(B)[2]
  alp = matrix(1, ncol = K, nrow = nbr_obs)
  somme = c()
  
  # On initialise.
  alp[1,] = PI * B[1,]
  
  for (t in 1:(nbr_obs-1)){
    a = (alp[t,] %*% A) %*% diag(B[t+1,])
    somme = c(somme,sum(a))
    alp[t+1,] = a / sum(a)
  }
  return(list(alp,somme,sum(alp[nbr_obs,])))
}
backward_2.0 = function( A, B){
  nbr_obs = dim(B)[1]
  K = dim(B)[2]
  
  # Création de la matrice initialisée (dernière ligne égale à 1).
  bet = matrix(1, ncol = K, nrow = nbr_obs)
  somme = c()
  
  for (t in (nbr_obs-1):1){
    b = A %*% (B[t+1,] * bet[t+1,])
    somme = c(somme,sum(b))
    bet[t,] = b / sum(b)
  }
  return(list(bet,somme))
}







################################################################################
###                   Initialisation et Résultat optimal                     ###                               
################################################################################

Result_opt = function(obs, N_etats, C, Q, J){
  T = dim(Obs)[[1]]
  Coef = c()
  Vitesses = c()
  
  # On gère les différentes dimensions.
  if (dimension == 2){Z = data.frame(obs$Z1,obs$Z2)}
  else {Z = obs$Z}
  
  # On découpe Z selon les différents états. Je vais simplement stocker les 
  # indices et non pas directement les valeurs des Z_i. 
  
  # Répartition.
  Z_rep = list()
  model = list()
  for (k in 1:N_etats){
    Z_rep[k] = c(0)
  }
  
  # On ne parcourt qu'une seule fois les données et on les répartit dans les 
  # différentes listes selon l'état prédit pour le déplacement. 
  for (i in 1:T){
    Z_rep[[Q[i]]] = c(Z_rep[[Q[i]]],i)   # On ajoute la coordonnée dans la bonne liste.
  }
  
  # On construit les différentes sous-parties de Z (autant que d'états).  
  for (i in 1:N_etats){
    l1 = c()
    l2 = c()
    C_nv = c()
    lgr = length(Z_rep[[i]])
    for (t in Z_rep[[i]][2:lgr]){
      l1 = c(l1,Z[t,1])
      l2 = c(l2,Z[t,2])
      C_nv = c(C_nv,C[t,])
    }
    C_nv = matrix(c(C_nv,C_nv), nrow = 2*length(l1),byrow = TRUE)
    model = lm(c(l1,l2) ~ C_nv)
    
    coef = coef(model)[1:J+1]
    Coef = c(Coef,coef)
  }
  
  # On s'occupe maintenant d'estimer la matrice de transition. 
  mcFitMLE <- markovchainFit(data = Q)
  A = matrix(mcFitMLE$estimate[1:N_etats],N_etats,N_etats)
  
  return(list(A,matrix(Coef, ncol = N_etats)))
  
}

initialisation = function(obs, N_etats, C, J, methode = 'kmeans', dimension = 2){
  nbr_obs = dim(Obs)[[1]]
  print(nbr_obs)
  Coef = c()
  Vitesses = c()
  
  if (methode == 'kmeans'){
    # On gère les différentes dimensions.
    if (dimension == 2){Z = data.frame('Z1' = obs$Z1[1:(nbr_obs-1)],
                                       'Z2' = obs$Z2[1:(nbr_obs-1)])}
    else {Z = obs$Z}
    # On effectue le kmeans sur les observations.
    km = kmeans(Z, N_etats)
    
    # On extrait la suite prédite des états. 
    Q_km = km$cluster
    print(paste(length(Q_km),'lgr Q_km'))
    # On découpe Z selon les différents états. Je vais simplement stocker les 
    # indices et non pas directement les valeurs des Z_i. 
    
    # Répartition.
    Z_rep = list()
    model = list()
    for (k in 1:N_etats){
      Z_rep[k] = c(0)
    }
    
    # On ne parcourt qu'une seule fois les données et on les répartit dans les 
    # différentes listes selon l'état prédit pour le déplacement. 
    for (i in 1:(nbr_obs-1)){
      Z_rep[[Q_km[i]]] = c(Z_rep[[Q_km[i]]],i)   # On ajoute la coordonnée dans la bonne liste.
    }
    
    # On construit les différentes sous-parties de Z (autant que d'états).  
    for (i in 1:N_etats){
      l1 = c()
      l2 = c()
      C_nv = c()
      lgr = length(Z_rep[[i]])
      for (t in Z_rep[[i]][2:lgr]){
        l1 = c(l1,Z[t,1])
        l2 = c(l2,Z[t,2])
        C_nv = c(C_nv,C[t,])
      }
      C_nv = matrix(c(C_nv,C_nv), nrow = 2*length(l1),byrow = TRUE)
      model = lm(c(l1,l2) ~ C_nv)
      vit = summary(model)$sigma
      coef = coef(model)[1:J+1]
      Coef[[i]] = coef
      Vitesses = c(Vitesses, vit)
    }
  }
  
  # On s'occupe maintenant d'estimer la matrice de transition. 
  #print(matrix(Q_km,1,T))
  mcFitMLE <- markovchainFit(data = Q_km)
  A = matrix(mcFitMLE$estimate[1:N_etats],N_etats,N_etats)
  
  return(list('A' = A, 'Beta' = Coef, 'Vitesses' = Vitesses))
}


################################################################################
###                               Viterbi                                    ###                               
################################################################################

retourner = function(liste){
  l = length(liste)
  liste_retournee = c()
  for (i in l:1){
    liste_retournee = c(liste_retournee, liste[i])
  }
  return(liste_retournee)
}

Viterbi = function(A,B,PI){
  T = dim(B)[1]
  K = dim(A)[1]
  
  # Création des matrices.
  delta = matrix(1,T,K)
  phi = matrix(0,T,K)
  
  # Initialisation de la matrice delta.
  delta[1,] = PI * B[1,]
  # Récurrence.
  for (t in 2:T){
    for (j in 1:K){
      
      # On calcule toutes les transitions possibles arrivant dans l'état j.
      dA = delta[t-1,] * A[,j] * 4
      
      # On trouve la transition la plus probable.
      Ind_max = which.max(dA)
      C_max = dA[Ind_max]
      
      # On modifie delta.
      delta[t,j] = C_max * B[t,j]
      
      # On modifie phi.
      phi[t,j] = Ind_max 
    }
  }
  
  # On construit maintenant la suite d'état la plus probable.
  
  # On prend l'état final le plus probable.
  fin_max = which.max(delta[T,])
  P_et = delta[T,fin_max]
  Q_et = c(fin_max)  # Initialisation de la suite d'état.
  for (t in (T-1):1){
    new_etat = phi[t+1,Q_et[T - t]]
    #print(new_etat)
    Q_et = c(Q_et, new_etat)
  }
  return(retourner(Q_et))
}



################################################################################
###                                 EM                                       ###                               
################################################################################

EM_Langevin_modif_A = function(obs, Lambda, delta, vit, C, G = 10, moyenne = FALSE){
  
  compteur = 0
  
  # On gère la dimension du modèle. 
  Dim = dim(obs)[2]
  if (Dim == 4){
    Z = cbind( obs$Z1, obs$Z2)
    dimension = 2
  }
  else {Z = obs$Z}
  
  nbr_obs = dim(Z)[1] - 1
  
  # Extraction des paramètres du modèle.
  A = Lambda$A
  B = Lambda$B[1:nbr_obs,]
  PI = Lambda$PI
  
  # On gère l'option moyenne si besoin.
  somme_theta = matrix(0,J,K)
  somme_A = matrix(0,K,K)
  
  
  # # Construction de la matrice C avec la division temporelle.
  # C_temp = C
  # for (i in 1:nbr_obs){
  #   C_temp[i] = C_temp[i]/sqrt(delta[i])
  #   C_temp[nbr_obs + i] = C_temp[nbr_obs+i]/sqrt(delta[i])
  # }
  
  
  while (compteur < G){
    print(paste('Tour',compteur))
    ### EXPECTATION.
    
    # GAMMA.
    forw = forward_2.0( A, B, PI)
    alp = forw[[1]]
    
    Back = backward_2.0( A, B)
    bet = Back[[1]]
    
    gam = alp * bet
    for (t in 1:dim(gam)[1]){gam[t,] = gam[t,]/(sum(gam[t,]))}
    
    # On gère la potentiel présence de NA dans la matrice gam.
    if (any(is.na(gam))){
      warning("Il y a présence d'au moins un NA dans la matrice gam, voici le dernier résultat")
      if (moyenne){return(list(somme_A/G,somme_theta/G,sqrt(vit)))}
      else {return(list(A,theta_nv,sqrt(vit)))}
    }
    
    
    ## CALCUL DE A.
    # Formule Article de Bilmes avec la division par beta au lieu de la 
    # renormalisation.
    Xi = array(1,dim = c( K, K, nbr_obs-1),)
    for (t in 1:(nbr_obs-1)){
      Xi[,,t] = diag(gam[t,] * (1/bet[t,])) %*% A %*% diag(B[t+1,] * bet[t+1,])
    }
    
    # Je fais la somme des Xi pour t allant de 1 à T-1.
    somme_Xi = matrix(0,K,K)
    for (t in 1:(nbr_obs-1)){somme_Xi = somme_Xi + Xi[,,t]}
    
    # Je fais la somme des gamma pour t allant de 1 à T-1.
    somme_gam = matrix(0, nrow = K, ncol = K, byrow = TRUE)
    for (k in 1:K){
      sg = sum(gam[1:nbr_obs-1,k])
      #print(matrix(sg, nrow= 1, ncol = K, byrow = TRUE))
      somme_gam[k,] = matrix(1/sg, nrow= 1, ncol = K, byrow = TRUE)
    }
    
    
    # On obtient l'estimateur de la matrice A.
    A = format_mat(somme_Xi * somme_gam)
    somme_A = somme_A + A
    
    
    # THETA.
    theta_nv = matrix(1,J,K)
    Vits = c()
    print(length(c(gam[,k],gam[,k])))
    for (k in 1:K){
      # On gère les deux cas différents selon la dimension.
      if (dimension == 2){
        model = lm(c(Z[1:nbr_obs,1],Z[1:nbr_obs,2]) ~ C, weights= c(gam[,k],gam[,k]))
        
      }
      else {
        model = lm(Z ~ C, weights=gam[,k])
      }
      
      # On récupère les coefficients.
      Vits = c(Vits, summary(model)$sigma)
      theta_nv[,k] = coef(model)[2:(J+1)]
    }
    # On gère la potentielle moyenne à calculer.
    somme_theta = somme_theta + theta_nv
    print(theta_nv)
    # On met à jour la matrice des probabilités des émissions.
    B = proba_emission(obs, C, theta_nv, delta, Vits)
    #browser()
    # On met à jour le compteur.
    compteur = compteur + 1
  }
  
  # On gère la moyenne si nécessaire.
  if (moyenne){return(list(somme_A/G,somme_theta/G,sqrt(vit)))}
  else {return(list(A,theta_nv,sqrt(Vits)))}
}

EM_Langevin_modif_Xi = function(obs, Lambda, delta, vit, C, G = 10, moyenne = FALSE){
  
  compteur = 0
  
  # On gère la dimension du modèle. 
  Dim = dim(obs)[2]
  if (Dim == 4){
    Z = cbind( obs$Z1, obs$Z2)
    dimension = 2
  }
  else {Z = obs$Z}
  
  nbr_obs = dim(Z)[1] - 1
  
  # Extraction des paramètres du modèle.
  A = Lambda$A
  B = Lambda$B[1:nbr_obs,]
  PI = Lambda$PI
  
  # On gère l'option moyenne si besoin.
  somme_theta = matrix(0,J,K)
  somme_A = matrix(0,K,K)
  
  
  # # Construction de la matrice C avec la division temporelle.
  # C_temp = C
  # for (i in 1:nbr_obs){
  #   C_temp[i] = C_temp[i]/sqrt(delta[i])
  #   C_temp[nbr_obs + i] = C_temp[nbr_obs+i]/sqrt(delta[i])
  # }
  
  
  while (compteur < G){
    print(paste('Tour',compteur))
    ### EXPECTATION.
    
    # GAMMA.
    forw = forward_2.0( A, B, PI)
    alp = forw[[1]]
    print(alp)
    
    Back = backward_2.0( A, B)
    bet = Back[[1]]
    print(bet)
    
    gam = alp * bet
    for (t in 1:dim(gam)[1]){gam[t,] = gam[t,]/(sum(gam[t,]))}
    print(gam)
    
    # On gère la potentiel présence de NA dans la matrice gam.
    if (any(is.na(gam))){
      warning("Il y a présence d'au moins un NA dans la matrice gam, voici le dernier résultat")
      if (moyenne){return(list(somme_A/G,somme_theta/G,sqrt(vit)))}
      else {return(list(A,theta_nv,sqrt(vit)))}
    }
    
    
    ## CALCUL DE A.
    
    Xi = array(1,dim = c( K, K, nbr_obs-1),)
    for (t in 1:(nbr_obs-1)){
      Xi[,,t] = diag(gam[t,]) %*% A %*% diag(B[t+1,] * bet[t+1,])
    }
    
    # Je fais la somme des Xi pour t allant de 1 à T-1.
    somme_Xi = matrix(0,K,K)
    for (t in 1:(nbr_obs-1)){somme_Xi = somme_Xi + Xi[,,t]}
    
    # Je fais la somme des gamma pour t allant de 1 à T-1.
    somme_gam = matrix(0, nrow = K, ncol = K, byrow = TRUE)
    for (k in 1:K){
      sg = sum(gam[1:nbr_obs-1,k])
      print(sg)
      #print(matrix(sg, nrow= 1, ncol = K, byrow = TRUE))
      somme_gam[k,] = matrix(1/sg, nrow= 1, ncol = K, byrow = TRUE)
    }
    print(somme_gam)
    
    # On obtient l'estimateur de la matrice A.
    A = format_mat(somme_Xi * somme_gam)
    somme_A = somme_A + A
    
    
    # THETA.
    theta_nv = matrix(1,J,K)
    Vits = c()
    print(length(c(gam[,k],gam[,k])))
    for (k in 1:K){
      # On gère les deux cas différents selon la dimension.
      if (dimension == 2){
        model = lm(c(Z[1:nbr_obs,1],Z[1:nbr_obs,2]) ~ C, weights= c(gam[,k],gam[,k]))
        
      }
      else {
        model = lm(Z ~ C, weights=gam[,k])
      }
      
      # On récupère les coefficients.
      Vits = c(Vits, summary(model)$sigma)
      theta_nv[,k] = coef(model)[2:(J+1)]
    }
    # On gère la potentielle moyenne à calculer.
    somme_theta = somme_theta + theta_nv
    print(theta_nv)
    # On met à jour la matrice des probabilités des émissions.
    B = proba_emission(obs, C, theta_nv, delta, Vits)
    #browser()
    # On met à jour le compteur.
    compteur = compteur + 1
  }
  
  # On gère la moyenne si nécessaire.
  if (moyenne){return(list(somme_A/G,somme_theta/G,sqrt(vit)))}
  else {return(list(A,theta_nv,sqrt(Vits)))}
}



E = EM_Langevin_modif_Xi( Obs, Lambda, incr, vit, C, G = 1
                         , moyenne = FALSE)



################################################################################
#                                                                              #
#                         Simulation des observations                          #
#                                                                              #
################################################################################       

nbr_obs = 5000      
K = 2       
J = 2        
dimension = 2  
vit = 0.4            
#PI = c(.5,.3,.2)    
PI = c(.7,.3)

# Paramètre de création des covariables. 
#seed = 1
lim <- c(-20, 20, -20, 20) # limits of map
resol <- 0.1 # grid resolution
rho <- 4; nu <- 1.5; sigma2 <- 10# Matern covariance parameters
mean_function <- function(z){# mean function
  -log(3 + sum(z^2))}



# Creation de la suite des instants.
tps_final = 1000
ano = 50 # nombre d'anomalies.

instants = seq(1, tps_final, length.out = (nbr_obs + ano))
anomalies = sample(1:(nbr_obs + ano),ano)
tps = instants[-anomalies]
incr = increments(tps)

# Creation de la liste des covariables via Rhabit.

liste_cov = list()
for (i in 1:J){
  liste_cov[[i]] = simSpatialCov(lim, nu, rho, sigma2, resol = resol,
                                 mean_function = mean_function,
                                 raster_like = TRUE)
}

# Creation de la suite des etats caches.

# A = matrix(c(.85,.05,.1,.03,.91,.06,.03,.07,.9),
#            ncol = K,
#            nrow = K,
#            byrow = TRUE)
A = matrix(c(.85,.15,.09,.91),
           ncol = K,
           nrow = K,
           byrow = TRUE)

Q = CM_generateur( A, nbr_obs)

# Le parametre de lien. 

theta = Nu(BETA(K,J), 1, vit)


theta

# Simulation des observations en utilisant Rhabit. 

Obs = Generation_observation3.0(beta = matrix_to_list(theta), Q, C = liste_cov, 
                                Vits = c(.4,.42), tps)


# On calcule les valeurs du gradient des covariables en les observations et 
# les met sous le bon format. 

MatObs = matrix(c(Obs$X1[1:(nbr_obs-1)],Obs$X2[1:(nbr_obs-1)]), (nbr_obs-1), 2, 
                byrow = FALSE)
CovGradLocs = covGradAtLocs(MatObs, liste_cov)
C = matrix(NA, 2*(nbr_obs-1), J)
for (t in 1:(nbr_obs-1)){
  for (j in 1:J){
    C[t,j] = CovGradLocs[t, j, 1]
    C[t - 1 + nbr_obs,j] = CovGradLocs[t, j, 2]
  }
}

# Construction de la matrice C avec la division temporelle.
# for (i in 1:(nbr_obs-1)){
#   C[i] = C[i]/sqrt(incr[i])
#   C[nbr_obs - 1 + i] = C[nbr_obs - 1 +i]/sqrt(incr[i])
# }


# On initialise les parametres. 

Init = initialisation(Obs, K, C, J)
A_init = Init$A; Beta_init = Init$Beta; Vits_init = Init$Vitesses


theta_initial = BetaToNu(Beta_init, Vits_init)
Lambda = list('A' = A,
              'B' = proba_emission(Obs, C, theta, incr,  Vits_init, 
                                   dimension),
              'PI' = PI)
Vits_init

E = EM_Langevin_modif_A( Obs, Lambda, incr, Vits_init, C, G = 20, moyenne = FALSE)
print(list(E[[1]],E[[2]],E[[3]]))
theta

A = Lambda$A
B = Lambda$B

nbr_obs = nbr_obs
Z = cbind( Obs$Z1, Obs$Z2)

alp = forward_2.0(Lambda$A, Lambda$B, PI)[[1]]
print(alp)
^bet = backward_2.0(Lambda$A, Lambda$B)[[1]]
gam = alp * bet
for (t in 1:dim(gam)[1]){gam[t,] = gam[t,]/sum(gam[t,])}



EM_Langevin_modif_A = function(obs, Lambda, delta, vit, C, G = 10,
                               moyenne = FALSE, dimension = 2){
  
  compteur = 0
  
  # On gère la dimension du modèle.
  
  if (dimension == 2){
    Z = cbind( obs$Z1, obs$Z2)
    dimension = 2
  }
  
  else {Z = obs$Z}
  nbr_obs = dim(Z)[1] - 1
  
  # Extraction des paramètres du modèle.
  A = Lambda$A
  B = Lambda$B[1:nbr_obs,]
  PI = Lambda$PI
  
  # On gère l'option moyenne si besoin.
  somme_theta = matrix(0,J,K)
  somme_A = matrix(0,K,K)
  
  
  # # Construction de la matrice C avec la division temporelle.
  # C_temp = C
  # for (i in 1:nbr_obs){
  #   C_temp[i] = C_temp[i]/sqrt(delta[i])
  #   C_temp[nbr_obs + i] = C_temp[nbr_obs+i]/sqrt(delta[i])
  # }
  while (compteur < G){
    print(paste('Tour',compteur))
    ### EXPECTATION.
    
    # GAMMA.
    alp = forward_2.0( A, B, PI)
    bet = backward_2.0( A, B)
    
    gam = alp * bet
    for (t in 1:dim(gam)[1]){gam[t,] = gam[t,]/(sum(gam[t,]))}
    print(gam)
    
    
    # On gère la potentiel présence de NA dans la matrice gam.
    if (any(is.na(gam))){
      warning("Il y a présence d'au moins un NA dans la matrice gam, voici le dernier résultat")
      if (moyenne){return(list(somme_A/G,somme_theta/G,sqrt(vit)))}
      else {return(list(A,theta_nv,sqrt(vit)))}
    }
    
    
    ## CALCUL DE A.
    
    Xi = array(1,dim = c( K, K, nbr_obs-1),)
    for (t in 1:(nbr_obs-2)){
      Xi[,,t] = diag(gam[t,] * (1/bet[t,])) %*% A %*% diag(B[t+1,] * bet[t+1,])
    }
    
    # Je fais la somme des Xi pour t allant de 1 à T-1.
    somme_Xi = matrix(0,K,K)
    for (t in 1:(nbr_obs-1)){somme_Xi = somme_Xi + Xi[,,t]}
    
    # Je fais la somme des gamma pour t allant de 1 à T-1.
    somme_gam = matrix(0, nrow = K, ncol = K, byrow = TRUE)
    for (k in 1:K){
      sg = sum(gam[1:nbr_obs-1,k])
      #print(matrix(sg, nrow= 1, ncol = K, byrow = TRUE))
      somme_gam[k,] = matrix(1/sg, nrow= 1, ncol = K, byrow = TRUE)
    }
    
    
    # On obtient l'estimateur de la matrice A.
    A = format_mat(somme_Xi * somme_gam)
    somme_A = somme_A + A
    
    
    # THETA.
    theta_nv = matrix(1,J,K)
    Vits = c()
    print(length(c(gam[,k],gam[,k])))
    for (k in 1:K){
      # On gère les deux cas différents selon la dimension.
      if (dimension == 2){
        model = lm(c(Z[1:nbr_obs,1],Z[1:nbr_obs,2]) ~ C, weights= c(gam[,k],gam[,k]))
        
      }
      else {
        model = lm(Z ~ C, weights=gam[,k])
      }
      
      # On récupère les coefficients.
      Vits = c(Vits, summary(model)$sigma)
      theta_nv[,k] = coef(model)[2:(J+1)]
    }
    # On gère la potentielle moyenne à calculer.
    somme_theta = somme_theta + theta_nv
    print(theta_nv)
    # On met à jour la matrice des probabilités des émissions.
    B = proba_emission(obs, C, theta_nv, delta, Vits)
    #browser()
    # On met à jour le compteur.
    compteur = compteur + 1
  }
  
  # On gère la moyenne si nécessaire.
  if (moyenne){return(list(A = somme_A/G,
                           Nu = somme_theta/G,
                           Vitesses = sqrt(Vits)))} else{return(list(A = A, 
                                                                     Nu = theta_nv, 
                                                                     Vitesses = sqrt(Vits)))}
}


