function dydt = ode_sirs(t, y, params, input_t, input_beta)
%ODE_SIRS Evaluate the derivatives for a time-varying SIRS model.
%
%   Syntax:
%       dydt = ode_sirs(t, y, params, input_t, input_beta)
%
%   Description:
%       Defines the Ordinary Differential Equations (ODE) for a Susceptible-
%       Infectious-Recovered-Susceptible model with time-varying transmission.
%
%       Dynamics:
%           S -> I : Infection (Driven by external Beta(t) curve)
%           I -> R : Recovery  (Driven by constant Gamma)
%           R -> S : Waning    (Driven by constant Xi)
%
%   Inputs:
%       t          - Current solver time (scalar).
%       y          - State vector [S; I; R].
%       params     - Structure containing biological constants:
%                    .gamma : Recovery rate [1/time].
%                    .xi    : Waning immunity rate [1/time].
%       input_t    - Time vector for the external transmission curve.
%       input_beta - Value vector for the external transmission curve.
%
%   Outputs:
%       dydt       - Column vector of derivatives [dS/dt; dI/dt; dR/dt].
%
%   See also HYBRID_FORECAST_ODE, ODE15S, INTERP1.

    %% 1. State Unpacking
    S = y(1); 
    I = y(2); 
    R = y(3);
    
    % Total population (N) is conserved, but calculated dynamically to
    % ensure mass balance in the frequency-dependent transmission term.
    N = S + I + R;
    
    %% 2. Forcing Function (Beta Interpolation)
    % The solver may query time points slightly outside the defined grid
    % (e.g., during intermediate steps). We clamp 't' to the input range
    % to prevent extrapolation errors.
    t_safe = max(min(t, max(input_t)), min(input_t));
    
    % Interpolate the transmission rate at the current solver time.
    % Linear interpolation is sufficient for dense grids.
    beta = interp1(input_t, input_beta, t_safe);
    
    %% 3. System Dynamics
    % dS/dt = -Beta*S*I/N + Xi*R
    % dI/dt = +Beta*S*I/N - Gamma*I
    % dR/dt = +Gamma*I    - Xi*R
    
    dS = -beta * (S * I / N) + params.xi * R;
    dI =  beta * (S * I / N) - params.gamma * I;
    dR =  params.gamma * I   - params.xi * R;
    
    %% 4. Output Packing
    % Return column vector for compatibility with standard ODE solvers.
    dydt = [dS; dI; dR]; 
    
end