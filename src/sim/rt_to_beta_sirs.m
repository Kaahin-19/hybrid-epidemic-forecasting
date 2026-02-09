function beta = rt_to_beta_sirs(Rt, gamma)
%RT_TO_BETA_SIRS Convert reproduction number Rt to transmission rate Beta.
%
%   Syntax:
%       beta = rt_to_beta_sirs(Rt, gamma)
%
%   Description:
%       Calculates the transmission rate (Beta) required to achieve a
%       target reproduction number (Rt) given a fixed recovery rate (Gamma).
%       This conversion is fundamental for SIR/SIRS models where the
%       differential equations are driven by Beta, but the experimental
%       design is defined in terms of Rt.
%
%       Formula: Beta(t) = Rt(t) * Gamma
%
%   Inputs:
%       Rt    - Reproduction number [dimensionless]. Can be a scalar or a
%               time-series vector.
%       gamma - Recovery rate [1/time]. Typically defined as 1/D_inf,
%               where D_inf is the infectious period.
%
%   Outputs:
%       beta  - Transmission rate [1/time]. Matches the dimensions of Rt.
%
%   See also GENERATE_SYNTHETIC_TRUTH, PARTA_CONFIG.

    if nargin < 2
        error('rt_to_beta_sirs:InsufficientInputs', ...
              'Both Rt and Gamma are required.');
    end

    % Perform element-wise multiplication to handle vector inputs
    beta = Rt .* gamma;
    
end