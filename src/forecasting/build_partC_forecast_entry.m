function scenario_entry = build_partC_forecast_entry(processed, cfg, exo_mode)
%BUILD_PARTC_FORECAST_ENTRY Build Part C real-data forecast inputs.
%
%   Syntax:
%       scenario_entry = build_partC_forecast_entry(processed, cfg, exo_mode)
%
%   Description:
%       Converts the processed Swedish COVID real-data artifact into the
%       shared Part A/B expanding-window forecast-entry format. Rt_est is
%       used as both the model input and evaluation target. I_scaled is used
%       as the ARX/I covariate and mapped to a normalized SIRS compatibility
%       state only for closed-loop ARX forecasting.
%
%   Inputs:
%       processed - Loaded Part C processed real-data artifact.
%       cfg       - Part C configuration structure.
%       exo_mode  - Exogenous mode, "None" or "I".
%
%   Outputs:
%       scenario_entry - Structure consumed by run_expanding_window_forecast.
%
%   See also PREPARE_WINDOW_DATA, RUN_EXPANDING_WINDOW_FORECAST.
%
% A. M. Kaahin 2026-06-03

    %% 1. Signal Preparation
    horizon = cfg.forecast.horizon;
    Rt_model_input = double(processed.Rt_est(:));
    Rt_evaluation_target = Rt_model_input;
    tspan = double(processed.t(:));
    I_scaled = double(processed.I_scaled(:));

    [S_model_input, I_model_input, U_true, compatibility_metadata] = ...
        local_compatibility_state(I_scaled, cfg, exo_mode);

    scenario_inputs = struct( ...
        'Rt_true', Rt_model_input, ...
        'tspan', tspan, ...
        'S_true', S_model_input, ...
        'I_true', I_model_input, ...
        'U_true', U_true);

    %% 2. Window Construction
    max_window_day = tspan(end) - horizon;
    windows = cfg.forecast.min_window : cfg.forecast.step_size : max_window_day;

    if isempty(windows)
        window_data = struct([]);
    else
        window_data = repmat(prepare_window_data(scenario_inputs, windows(1), ...
            horizon, cfg.sirs_projection), numel(windows), 1);
        for w = 1:numel(windows)
            window_data(w) = prepare_window_data(scenario_inputs, windows(w), ...
                horizon, cfg.sirs_projection);
            if window_data(w).is_valid_window
                idx = window_data(w).horizon_indices;
                if max(idx) <= numel(Rt_evaluation_target)
                    window_data(w).truth_Rt = Rt_evaluation_target(idx);
                else
                    window_data(w).is_valid_window = false;
                end
            end
        end
    end

    %% 3. Output Assembly
    scenario_entry = struct();
    scenario_entry.scenario_id = "real";
    scenario_entry.scenario_name = "WHO-derived Sweden Rt estimate";
    scenario_entry.num_exo = size(U_true, 2);
    scenario_entry.windows = windows(:);
    scenario_entry.window_data = window_data;
    scenario_entry.Rt_true = Rt_evaluation_target;
    scenario_entry.Rt_model_input = Rt_model_input;
    scenario_entry.tspan = tspan;
    scenario_entry.U_true = U_true;
    scenario_entry.S_model_input = S_model_input;
    scenario_entry.I_model_input = I_model_input;
    scenario_entry.compatibility_metadata = compatibility_metadata;
end

function [S_model_input, I_model_input, U_true, metadata] = ...
    local_compatibility_state(I_scaled, cfg, exo_mode)
%LOCAL_COMPATIBILITY_STATE Build the explicit Part C ARX state proxy.
    I_scaled = double(I_scaled(:));
    pop_size = double(cfg.sirs_projection.pop_size);
    max_fraction = 1 - (1 / pop_size);
    I_fraction = min(max(I_scaled, 0), max_fraction);
    I_model_input = I_fraction * pop_size;
    S_model_input = pop_size - I_model_input;
    S_model_input = max(S_model_input, 1);
    total_si = S_model_input + I_model_input;
    S_model_input = S_model_input .* (pop_size ./ total_si);
    I_model_input = I_model_input .* (pop_size ./ total_si);

    switch char(exo_mode)
        case 'None'
            U_true = [];
        case 'I'
            U_true = I_scaled;
        otherwise
            error('FORECAST:UnsupportedExoMode', ...
                'Part C supports only None and I exogenous modes.');
    end

    metadata = struct();
    metadata.Rt_model_input = "Rt_est";
    metadata.Rt_evaluation_target = "Rt_est";
    metadata.I_model_input = ...
        "I_scaled mapped to a normalized compatibility state";
    metadata.S_model_input = ...
        "Neutral complement to I_scaled for closed-loop ARX compatibility only";
    metadata.U_true = "I_scaled for ARX/I; empty for AR/None";
    metadata.pop_size = pop_size;
    metadata.max_state_fraction = max_fraction;
    metadata.biological_interpretation = ...
        "The Part C S/I state is not an observed Swedish susceptible trajectory.";
end
