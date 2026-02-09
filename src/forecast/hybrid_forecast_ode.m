function [t_grid, I_forecast, U_full] = hybrid_forecast_ode(u0, Rt_trajectory, dynrates, dt)
%HYBRID_FORECAST_ODE Run the SIRS ODE forward using a predicted Rt curve.
%
%   Syntax:
%       [t_grid, I_forecast, U_full] = hybrid_forecast_ode(u0, Rt_trajectory, dynrates)
%       [t_grid, I_forecast, U_full] = hybrid_forecast_ode(u0, Rt_trajectory, dynrates, dt)
%
%   Description:
%       Implements the "Mechanistic" component of the Hybrid framework.
%       It translates a forecasted Rt trajectory into a transmission rate
%       (Beta) curve and solves the differential equations (ODE) to project
%       the future state of the epidemic (S, I, R).
%
%       Solver: Uses ode15s (stiff solver) to ensure stability even with
%       rapid changes in the transmission rate.
%
%   Inputs:
%       u0            - Initial state vector [S; I; R] at t=0 (current day).
%       Rt_trajectory - Vector of Rt values (Current Day + Forecast Horizon).
%       dynrates      - Struct containing biological parameters (.gamma, .xi).
%       dt            - (Optional) Time step [days]. Default: 1.
%
%   Outputs:
%       t_grid     - Time vector relative to start [0, dt, ..., horizon].
%       I_forecast - Vector of predicted Infected cases matching t_grid.
%       U_full     - Full state matrix [3 x N] containing [S; I; R] at each step.
%
%   See also PARTA_02_RUN_FORECASTS, ODE_SIRS, RT_TO_BETA_SIRS.

    if nargin < 4, dt = 1; end

    %% 1. Parameter Translation
    % Convert the forecasted Rt curve into a transmission rate (Beta) curve
    % consistent with the SIRS model physics.
    beta_curve = rt_to_beta_sirs(Rt_trajectory, dynrates.gamma);
    
    %% 2. Time Grid Setup
    % Define the discrete time steps for the solver output.
    horizon_steps = length(Rt_trajectory) - 1;
    t_grid = 0 : dt : horizon_steps;
    
    % Safety Check: Ensure Beta curve matches the time grid dimensions
    if length(t_grid) ~= length(beta_curve)
        error('Dimension Mismatch: Time steps (%d) != Beta points (%d)', ...
            length(t_grid), length(beta_curve));
    end
    
    %% 3. Solver Configuration
    % Create an anonymous function to freeze parameters and input curves,
    % presenting a standard f(t,y) interface to the ODE solver.
    ode_fun = @(t, y) ode_sirs(t, y, dynrates, t_grid, beta_curve);
    
    %% 4. Execution
    % Run the stiff ODE solver (ode15s) to integrate the system forward.
    [~, U_trans] = ode15s(ode_fun, t_grid, u0);
    
    %% 5. Formatting
    % Transpose result to standard [State x Time] format
    U_full = U_trans';       
    
    % Extract the "Infected" compartment (Row 2) for forecast plotting
    I_forecast = U_full(2, :);
    
end