function umod = genData(name,seed,dynrates)
%GENDATA Generate data from model using URDME.
%   UMOD = GENDATA('name') generates synthetic data from the model
%   with name 'name' using URDME. If nargout == 0, the result is
%   stored as data/['umod' 'name'].mat.
%
%   Care is taken to ensure quasi-stationary initial data. The initial
%   number of individuals in the infected compartment is set to 500.
%
%   UMOD = GENDATA('name',SEED) additionally initializes the random
%   number generator with a specified seed. Use SEED = [] for the
%   default.
%
%   UMOD = GENDATA('name',SEED,DYNRATES) supports inputing the dynamic
%   rates of the model as a struct with the correct fields.
%
%   Name      Description
%   ------------------------------------------------------------
%   SIS       Classical SIS-model
%   SIRS      Classical SIR(S)-model
%   SISe      As SIS but with environmental spread instead
%   SIRSe     As SIRS but with environmental spread instead
%
%   SIHDR     SIR-model with added (H)ospitalized
%             and (D)eath compartments
%   SIHDRe    As SIDHR but with environmental spread instead
%
%   C19       SIHDR-model with added (E)xposed, (A)symptomatic and (W)orsen
%             compartments
%   C19e      As C19 but with environmental spread instead
%
%   Model parameters are static to this file.

% S. Engblom 2024-11-22 (Major revision, updated to URDME 1.45)
% D. Emanuelsson, D. Lood, E. Rimhagen 2023-11-21 (added C19 and C19e)
% S. Engblom 2023-11-06 (revision)
% J. Evaeus 2023-10-20 (added inputs seed and dynrates for DynOpt bootstrap)
% S. Engblom 2023-09-21 (added SISe)
% S. Engblom 2023-08-25 (added SIR and SIHR)
% S. Engblom 2022-12-15 (SIHRe removed)
% S. Engblom 2022-12-08 (SIS added)
% S. Engblom 2022-05-18 (Restructured from generateSIReBranch)
% S. Engblom 2022-05-06

% Models currently generated:
%
% * SIS:
% ------
% The simplest model
%
% S > beta*S/Sigma*I > I
% I > gammaI*I > S
% 
% States: (S,I) = (Susceptible, Infected).
%
% Parameters: (Sigma,beta,gammaI) = (Population, infectivity,
% infectious time).
%
% R0 = beta/gammaI.
%
% * SIRS:
% ------
% S > beta*S/Sigma*I > I
% I > gammaI*I > R
% R > deltaR*R > S
% 
% States: (S,I,R) = (Susceptible, Infected, Recovered).
%
% New parameter deltaR, the time until susceptibility is retrieved. R0
% as the SIS-model.
%
% * SISe:
% -------
% The simplest environmental model
%
% S > beta*S/Sigma*P > I
% I > gammaI*I > S
% I > rhoP*I > I+P
% P > rhoP*P > @
%
% States: (S,I,P) = (Susceptible, Infected, infectious Pressure).
%
% New parameter rhoP, infectious pressure decay. R0 as the SIS-model.
%
% * SIRSe:
% -------
% S > beta*S/Sigma*P > I
% I > gammaI*I > R
% R > deltaR*R > S
% I > rhoP*I > I+P
% P > rhoP*P > @
%
% States: (S,I,R,P) = (Susceptible, Infected, Recovered, infectious
% Pressure).
%
% * SIHDR:
% --------
% This model adds a severity aspect.
%
% S > beta*S/Sigma*I > I
% I > gammaI*FIH*I > H
% I > gammaI*FID*I > D
% I > gammaI*(1-FIH-FID)*I > R
% H > gammaH*H*FHD > D
% H > gammaH*H*(1-FHD) > R
% 
% States: (S,I,H,R,D) = (Susceptible, Infected, Hospitalized,
% Recovered, Dead).
%
% Parameters: (Sigma,beta,FIH,FID,FHD,gammaI,gammaH) = (Population,
% infectivity, severity/hospitalization, severity/fatality, fatality
% at hospital, infectious time, hospitalization time).
%
% The total IFR is given by FID+FIH*FHD. Also, R0 = beta/gammaI.
%
% * SIHDRe:
% ---------
% Same as SIHDR but driven by an environmental compartment P.
%
% S > beta*S/Sigma*P > I
% I > rhoP*I > I+P
% P > rhoP*P > @
%
% States: (S,I,H,D,R,P).
%
% * C19:
% ---------
% Proposed model for Covid-19.
% 
% S > beta*S*(thetaE*E+thetaA*A+thetaI*I)/Sigma > E
% E > sigma*(FEI)*E  > I
% E > sigma*(1-FEI)*E > A
% A > gammaI*A > R
% I > gammaI*FIH*I > H
% I > gammaI*FID*I > D
% I > gammaI*(1-FIH-FID)*I  > R
% H > gammaH*FHD*H > D
% H > gammaH*FHW*H > W
% H > gammaH*(1-FHD-FHW)*H  > R
% W > gammaW*FWD*W > D
% W > gammaW*(1-FWD)*W > H
%
% with thetaI = 1 by non-dimensionalization.
%
% States: (S,E,A,I,H,W,D,R) = (Susceptible, Exposed, Asymptomatic,
% Infected, Hospitalized, Worsen/@ICU, Dead, Recovered).
%
% Parameters: (Sigma,beta,thetaE,thetaA,thetaI,FEI,FIH,FID,FHD,
% FHW,FWD,sigma,gammaI,gammaH,gammaW) = (Population, infectivity,
% viral shedding from E/A/I, exposure/severity,
% severity/hospitalization, severity/fatality, fatality at hospital,
% hospitalization/ICU, fatality at ICU, exposure time, infectious
% time, hospitalization time, ICU time).
%
% The total IFR is given by FEI*(FID+(FHD+FHW)*FWD*FIH/(1-x)), with x
% = FHW*(1-FWD). Also, R0 = beta*(thetaE/sigma + (1-FEI)*thetaA/gammaI
% + FEI/gammaI).
%
% * C19e:
% ---------
% Same as C19 but driven by an environmental compartment P [1].
%
% S > beta*S/Sigma*P > I
% E+A+I > rhoP*(thetaE*E+thetaA*E+I) > E+A+I+P
% P > rhoP*P > @
%
% States: (S,E,A,I,H,W,D,R,P).
%
% Reference:
%   [1] R. Marin, H. Runvik, A. Medvedev, S. Engblom: "Bayesian
%   monitoring of COVID-19 in Sweden", Epidemics 45 (2023),
%   doi: 10.1016/j.epidem.2023.100715

% input seed
if nargin < 2
  rng(220506); % reproducible results 
elseif ~isempty(seed)
  rng(seed); % (affects randi, which goes into urdme)
end

switch name
  case {'SIS' 'SIRS' 'SISe' 'SIRSe'}
    % rate names
    rates.beta = 'ldata_time';
    rates.gammaI = 'gdata';

    % species and transitions (minor differences)
    switch name
      case 'SIS'
        species = {'S' 'I'};
        r = {'S > beta*S*I/vol > I' ...
             'I > gammaI*I > S'};
      case 'SIRS'
        species = {'S' 'I' 'R'};
        r = {'S > beta*S*I/vol > I' ...
             'I > gammaI*I > R' ...
             'R > deltaR*R > S'};
        rates.deltaR = 'gdata';
      case 'SISe'
        species = {'S' 'I' 'P'};
        r = {'S > beta*P*S/vol > I' ...
             'I > gammaI*I > S' ...
             'I > rhoP*I > I+P' ...
             'P > rhoP*P > @'};
        rates.rhoP = 'gdata';
      case 'SIRSe'
        species = {'S' 'I' 'R' 'P'};
        r = {'S > beta*P*S/vol > I' ...
             'I > gammaI*I > R' ...
             'R > deltaR*R > S' ...
             'I > rhoP*I > I+P' ...
             'P > rhoP*P > @'};
        rates.deltaR = 'gdata';
        rates.rhoP = 'gdata';
    end

    % sort it out
    umod = rparse([],r,species,rates,name);

    % add the rest
    umod.vol = 1e5;
    Nspecies = size(umod.N,1);
    umod.D = sparse(Nspecies,Nspecies);
    umod.sd = 1;
    umod.u0 = zeros(Nspecies,1);
    umod.tspan = 0:140;

    % static rates
    Sigma = umod.vol;
    gammaI = 1/7;
    deltaR = 0;
    tauP = 1; rhoP = -log(0.5)/tauP; % half-time of one day

    % dynamic rates
    if nargin < 3
      % load R0 as a time-series
      load data/R0a
      R0 = ppval(umod.tspan,R0);
      beta = R0*gammaI;
    else
      beta = dynrates.beta;
      R0 = beta/gammaI;
    end

    % static rates
    Rates.gammaI = gammaI;
    if any(name == 'R')
      Rates.deltaR = deltaR;
    end
    if any(name == 'e')
      Rates.rhoP = rhoP;
    end
    if ~isequal(fieldnames(Rates),umod.private.rp.RateNames(2:end)')
      error('It seems the ordering of rate parameters differ.');
    end

    % convert into Mrates-by-1 matrix:
    GDATA = struct2cell(Rates);
    GDATA = cat(1,GDATA{:});

    % parse and compile
    umod = urdme(umod,'solve',0,'compile',1,'solver','ssa', ...
                 'modelname',name, ...
                 'gdata',GDATA, ...
                 'ldata_time', ...
                 reshape(beta,[1 numel(umod.vol) numel(umod.tspan)]), ...
                 'data_time',umod.tspan);
    umod.solve = 1;
    umod.parse = 1; % safety
    umod.compile = 0;

    % add rates as a private struct 'epiid'
    umod.private.epiid.R0 = R0;
    umod.private.epiid.rates = Rates;
    umod.private.epiid.dynrates = struct('beta',beta);
    % also add propensities as private field:
    for i = 1:numel(r)
      ix = find(r{i} == '>');
      prop{i} = r{i}(ix(1)+1:ix(2)-1);
    end
    umod.private.epiid.Propensities = prop;

    % straightforward initiation and simulation
    umod.u0(1:2) = [umod.vol-500 500]';
    if any(name == 'e')
      umod.u0(end) = umod.u0(2); % assume stationary P
    end
    umod.seed = randi(intmax);
    umod = urdme(umod);

  case {'SIHDR' 'SIHDRe'}
    % rate names
    rates.beta = 'ldata_time';
    rates.FID = 'ldata_time';
    rates.gammaI = 'gdata';
    rates.gammaH = 'gdata';
    rates.FIH = 'gdata';
    rates.FHD = 'gdata';

    % species and transitions (minor differences)
    switch name
      case 'SIHDR'
        species = {'S' 'I' 'H' 'D' 'R'};
        r = cell(1,6);
        r{1} = 'S > beta*S*I/vol > I';
        r{2} = 'I > gammaI*FIH*I > H';
        r{3} = 'I > gammaI*FID*I > D';
        r{4} = 'I > gammaI*(1-FIH-FID)*I > R';
        r{5} = 'H > gammaH*FHD*H > D';
        r{6} = 'H > gammaH*(1-FHD)*H > R';
      case 'SIHDRe'
        species = {'S' 'I' 'H' 'D' 'R' 'P'};
        r = cell(1,8);
        r{1} = 'S > beta*S*P/vol > I';
        r{2} = 'I > gammaI*FIH*I > H';
        r{3} = 'I > gammaI*FID*I > D';
        r{4} = 'I > gammaI*(1-FIH-FID)*I > R';
        r{5} = 'H > gammaH*FHD*H > D';
        r{6} = 'H > gammaH*(1-FHD)*H > R';
        r{7} = 'I > rhoP*I > I+P';
        r{8} = 'P > rhoP*P > @';
        rates.rhoP = 'gdata';
    end

    % sort it out
    umod = rparse([],r,species,rates,name);

    % add the rest
    umod.vol = 1e5;
    Nspecies = size(umod.N,1);
    umod.D = sparse(Nspecies,Nspecies);
    umod.sd = 1;
    umod.u0 = zeros(Nspecies,1);
    umod.tspan = 0:140;

    % static rates
    Sigma = umod.vol;
    gammaI = 1/7;
    gammaH = 1/10;
    FIH = 0.02;
    FHD = 0.10;
    tauP = 1; rhoP = -log(0.5)/tauP; % half-time of one day

    % dynamic rates
    if nargin < 3
      % load R0 as a time-series
      load data/R0b

      % load the severity as a time-series
      load data/F
      % (the overall IFR)

      R0 = ppval(umod.tspan,R0);
      beta = R0*gammaI;
      IFR = ppval(umod.tspan,F);
      FID = IFR-FIH*FHD;
      % (since the total IFR = FID+FIH*FHD)
    else
      beta = dynrates.beta;
      R0 = beta/gammaI;
      
      FID = dynrates.FID;
      IFR = FID+FIH*FHD;
    end

    % static rates
    Rates.gammaI = gammaI;
    Rates.gammaH = gammaH;
    Rates.FIH = FIH;
    Rates.FHD = FHD;
    if any(name == 'e')
      Rates.rhoP = rhoP;
    end
    if ~isequal(fieldnames(Rates),umod.private.rp.RateNames(3:end)')
      error('It seems the ordering of rate parameters differ.');
    end

    % convert into Mrates-by-1 matrix:
    GDATA = struct2cell(Rates);
    GDATA = cat(1,GDATA{:});

    % parse and compile
    umod = urdme(umod,'solve',0,'compile',1,'solver','ssa', ...
                 'modelname',name, ...
                 'gdata',GDATA, ...
                 'ldata_time', ...
                 reshape([beta; FID],[2 numel(umod.vol) numel(umod.tspan)]), ...
                 'data_time',umod.tspan);
    umod.solve = 1;
    umod.parse = 1; % safety
    umod.compile = 0;
    
    % add rates as private fields
    umod.private.epiid.R0 = R0;
    umod.private.epiid.IFR = IFR;
    umod.private.epiid.rates = Rates;
    umod.private.epiid.dynrates = struct('beta',beta,'FID',FID);
    % add propensities as private field
    for i = 1:numel(r)
      ix = find(r{i} == '>');
      prop{i} = r{i}(ix(1)+1:ix(2)-1);
    end
    umod.private.epiid.Propensities = prop;

    % straightforward initiation and simulation
    I = 500; % set
    H = round(gammaI/gammaH*FIH*I); % stationary H
    umod.u0(1:3) = [umod.vol-I-H I H];
    if any(name == 'e')
      umod.u0(end) = umod.u0(2); % stationary P
    end
    umod.seed = randi(intmax);
    umod = urdme(umod);

  case {'C19' 'C19e'}
    % rate names
    rates.beta = 'ldata_time';
    rates.FID = 'ldata_time';
    rates.sigma = 'gdata';
    rates.gammaI = 'gdata';
    rates.gammaH = 'gdata';
    rates.gammaW = 'gdata';
    rates.FEI = 'gdata';
    rates.FIH = 'gdata';
    rates.FHW = 'gdata';
    rates.FHD = 'gdata';
    rates.FWD = 'gdata';
    rates.thetaE = 'gdata';
    rates.thetaA = 'gdata';

    % species and transitions (minor differences)
    switch name
      case 'C19'
        species = {'S' 'E' 'A' 'I' 'H' 'W' 'D' 'R'};
        r = cell(1,12);
        r{1} = 'S > beta*S*(thetaE*E+thetaA*A+I)/vol > E';
        r{2} = 'E > sigma*FEI*E  > I';
        r{3} = 'E > sigma*(1-FEI)*E > A';
        r{4} = 'A > gammaI*A > R';  
        r{5} = 'I > gammaI*FIH*I > H';
        r{6} = 'I > gammaI*FID*I > D';
        r{7} = 'I > gammaI*(1-FIH-FID)*I  > R';
        r{8} = 'H > gammaH*FHD*H > D';
        r{9} = 'H > gammaH*FHW*H > W';
        r{10} = 'H > gammaH*(1-FHD-FHW)*H  > R';
        r{11} = 'W > gammaW*FWD*W > D';
        r{12} = 'W > gammaW*(1-FWD)*W > H';
      case 'C19e'
        species = {'S' 'E' 'A' 'I' 'H' 'W' 'D' 'R' 'P'};
        r = cell(1,14);
        r{1} = 'S > beta*S*P/vol > E';
        r{2} = 'E > sigma*FEI*E  > I';
        r{3} = 'E > sigma*(1-FEI)*E > A';
        r{4} = 'A > gammaI*A > R';  
        r{5} = 'I > gammaI*FIH*I > H';
        r{6} = 'I > gammaI*FID*I > D';
        r{7} = 'I > gammaI*(1-FIH-FID)*I  > R';
        r{8} = 'H > gammaH*FHD*H > D';
        r{9} = 'H > gammaH*FHW*H > W';
        r{10} = 'H > gammaH*(1-FHD-FHW)*H  > R';
        r{11} = 'W > gammaW*FWD*W > D';
        r{12} = 'W > gammaW*(1-FWD)*W > H';
        r{13} = 'E+A+I > rhoP*(thetaE*E+thetaA*A+I) > E+A+I+P';
        r{14} = 'P > rhoP*P > @';
        rates.rhoP = 'gdata';
    end
    
    % sort it out
    umod = rparse([],r,species,rates,name);

    % add the rest
    umod.vol = 1e5;
    Nspecies = size(umod.N,1);
    umod.D = sparse(Nspecies,Nspecies);
    umod.sd = 1;
    umod.u0 = zeros(Nspecies,1);
    umod.tspan = 0:280;

    % static rates
    Sigma = umod.vol;
    sigma = 1/6.3;
    gammaI = 1/7.5;
    gammaH = 1/8.9;
    gammaW = 1/13;
    FEI = 0.76;
    FIH = 0.038;
    FHW = 0.11;
    FHD = 0.1322;
    FWD = 0.2129;
    % note: non-dimensional parameters, see SI in [1] (where these
    % are denoted thetaE* and thetaA*, respectively)
    thetaE = 1.1;
    thetaA = 0.97;
    tau = 1; rhoP = -log(0.5)/tau; % half-time of one day

    % dynamic rates - adjusted to mimic the real case from [1]
    if nargin < 3
      % load R0 as a time-series
      load data/R0c

      % load the severity as a time-series
      load data/F
      % (the overall IFR)

      R0 = ppval(umod.tspan,R0); % mean ~ 1.25
      IFR = ppval(umod.tspan/2,F); % (note: new tspan)
      IFR = IFR-min(IFR);
      IFR = 0.5e-2/max(IFR)*IFR+0.5e-2; % in [0.5,1.0]%

      % Eq (9) in the SI of [1], using gammaA = gammaI and F1 = 0
      beta = R0/(thetaE/sigma + (1-FEI)*thetaA/gammaI + FEI/gammaI);

      % Eq (17), same source
      x = FHW*(1-FWD);
      FID = (IFR/FEI)-(FHD/FWD+FHW)*FWD*FIH/(1-x);
      assert(all(0 < FID & FID < 0.7e-2));
    else
      beta = dynrates.beta;
      R0 = beta*(thetaE/sigma + (1-FEI)*thetaA/gammaI + FEI/gammaI);
      FID = dynrates.FID;
      x = FHW*(1-FWD);
      IFR = FEI*(FID + (FHD/FWD+FHW)*FWD*FIH/(1-x));
    end

    % static rates
    Rates.sigma = sigma;
    Rates.gammaI = gammaI;
    Rates.gammaH = gammaH;
    Rates.gammaW = gammaW;
    Rates.FEI = FEI;
    Rates.FIH = FIH;
    Rates.FHW = FHW;
    Rates.FHD = FHD;
    Rates.FWD = FWD;
    Rates.thetaE = thetaE;
    Rates.thetaA = thetaA;
    if any(name == 'e')
      Rates.rhoP = rhoP;
    end
    if ~isequal(fieldnames(Rates),umod.private.rp.RateNames(3:end)')
      error('It seems the ordering of rate parameters differ.');
    end

    % convert into Mrates-by-1 matrix:
    GDATA = struct2cell(Rates);
    GDATA = cat(1,GDATA{:});

    % parse and compile
    umod = urdme(umod,'solve',0,'compile',1,'solver','ssa', ...
                 'modelname',name, ...
                 'gdata',GDATA, ...
                 'ldata_time', ...
                 reshape([beta; FID],[2 numel(umod.vol) numel(umod.tspan)]), ...
                 'data_time',umod.tspan);
    umod.solve = 1;
    umod.parse = 1; % safety
    umod.compile = 0;

    % add rates as private fields
    umod.private.epiid.R0 = R0;
    umod.private.epiid.IFR = IFR;
    umod.private.epiid.rates = Rates;
    umod.private.epiid.dynrates = struct('beta',beta,'FID',FID);
    % add propensities as private field
    for i = 1:numel(r)
      ix = find(r{i} == '>');
      prop{i} = r{i}(ix(1)+1:ix(2)-1);
    end
    umod.private.epiid.Propensities = prop;

    I = 500; % set
    E = round(gammaI/sigma*I/FEI); % stationarity I
    A = round(sigma*E*(1-FEI)/gammaI); % stationarity A 
    H = round(gammaI*I*FIH/gammaH); % stationary H
    W = round(gammaH*H*FHW/gammaW); % stationarity W
    umod.u0(1:6) = [umod.vol-E-A-I-H-W E A I H W];
    if any(name == 'e')
      umod.u0(end) = round(thetaE*E+thetaA*A+I); % stationary P
    end
    umod.seed = randi(intmax);
    umod = urdme(umod);

  otherwise, error('Unknown model name.');
end

% save to file if umod is not returned
if nargout == 0
  save(['data/umod_' name '.mat'],'umod');
end

% ----------------------------------------------------------------------
function [x,y] = l_getxy(ax)
%L_GETXY Gets a series of coordinates (X,Y).
%   [X,Y] = L_GETXY(AX) sets the axis AX and collects mouse cursor
%   clicks. Exit by pressing space.

% this is actually more of a cut-and-paste function...
ax = [0 280 0 2.5];
clf, axis(ax); hold on, grid on, set(gca,'xtick',ax(1):7:ax(2));
tspan = ax(1):ax(2);

a = 1.05;
b = 0.5;
f = 3*2*pi/tspan(end);
c = -0.35/tspan(end);

R0 = (a+b*sin(f*tspan)).*exp(-c*tspan);
mean(R0), minmax(R0)
figure(1), plot(tspan,R0)

n = 0;
x = zeros(1,0); y = zeros(1,0);
while true
  [xx,yy,button] = ginput(1);
  if button == ' '; break; end % end with space
  n = n+1;
  x(n) = xx;
  y(n) = yy;
  plot(xx,yy,'.k');
  hold on, plot(tspan,R0),
  drawnow,
end

R0 = pchip(x,y);
save('data/R0c','R0');

% ----------------------------------------------------------------------
function [tspan,R0] = l_sinR0
%L_sinR0 Sinusoidal R0.
%   [tspan,R0] = L_sinR0 returns an R0-series from a sinus.

% this is actually more of a cut-and-paste function...
tspan = 0:280;

a = 1.05;
b = 0.5;
f = 3*2*pi/tspan(end);
c = -0.35/tspan(end);

R0 = (a+b*sin(f*tspan)).*exp(-c*tspan);
mean(R0), minmax(R0)
figure(1), plot(tspan,R0)

R0 = spline(tspan,R0);
save('data/R0c','R0');

name = 'C19e';
umod = genData(name);
inc = name(end) == 'e';
figure(2),
subplot(3,1,1);
plot(tspan,umod.U(4+inc,:)./umod.vol*100);
subplot(3,1,2);
plot(tspan,umod.U(5+inc,:));
subplot(3,1,3);
plot(tspan,umod.U(6+inc,:));
umod.U(1+inc,[1 100 200 end])/umod.vol % S

% ----------------------------------------------------------------------