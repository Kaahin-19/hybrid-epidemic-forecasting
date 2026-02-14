function [t_grid, I_forecast, U_full] = hybrid_forecast_ode(u0, Rt_trajectory, dynrates)
%HYBRID_FORECAST_ODE Project epidemic state using deterministic URDME solver.
%
%   [t, I, U] = HYBRID_FORECAST_ODE(u0, Rt, rates) runs the SIRS model
%   forward using the URDME 'uds' solver. It caches the compiled model 
%   to ensure efficiency during repeated calls.
%
%   Inputs:
%       u0            - Initial state vector [S; I; R] (3x1).
%       Rt_trajectory - Vector of time-varying effective reproduction numbers.
%       dynrates      - Struct containing biological parameters (.gamma, .xi).
%
%   Outputs:
%       t_grid     - Time vector corresponding to the forecast (1 x T).
%       I_forecast - Vector of projected infected population counts (1 x T).
%       U_full     - Full state matrix [3 x T].
%
%   See also GENDATA, URDME, UDS.

    % Persistent cache to prevent unnecessary recompilation
    persistent cached_umod cached_rates

    % Recompile only if parameters change or cache is empty
    if isempty(cached_umod) || ~isequal(cached_rates, dynrates)
        umod = genData('SIRS', [], dynrates);
        cached_umod = umod;
        cached_rates = dynrates;
    else
        umod = cached_umod;
    end

    % 1. Configure Time Grid
    horizon_steps = length(Rt_trajectory) - 1;
    t_grid = 0 : 1 : horizon_steps;

    % 2. Prepare Time-Varying Parameters
    % Convert Rt to beta and reshape for URDME [1 x 1 x T]
    beta_curve = rt_to_beta_sirs(Rt_trajectory, dynrates.gamma);
    new_ldata = reshape(beta_curve, [1, 1, length(beta_curve)]);

    % 3. Update Model State
    umod.tspan = t_grid;         
    umod.data_time = t_grid;     
    umod.ldata_time = new_ldata; 
    umod.vol = sum(u0);
    umod.u0 = u0;

    % 4. Solver Configuration
    umod.compile = 0; % Use existing MEX file

    % 5. Execute Solver
    data = urdme(umod, 'solver', 'uds');

    % 6. Extract Results
    U_full = data.U;
    I_forecast = U_full(2, :);

end