function outPath = plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%PLOT_RT_FORECAST_COMPARISON Export a legacy forecast-comparison figure.
%
%   Syntax:
%       outPath = plot_rt_forecast_comparison(results, Rt_true, tspan, plot_name, cfg)
%
%   Description:
%       Compatibility wrapper for older Part B/C scripts. New Part A figure
%       generation should call plot_forecast_comparison and export_figure
%       directly with an explicit plot_spec.
%
%   Inputs:
%       results   - Struct array of forecast results per window.
%       Rt_true   - Numeric vector of the ground-truth effective-Rt curve.
%       tspan     - Numeric vector of time points.
%       plot_name - String identifier for the plot title (scenario name).
%       cfg       - Configuration struct containing output directories.
%
%   Outputs:
%       outPath   - Absolute path to the saved forecast-comparison figure.
%
%   See also PLOT_FORECAST_COMPARISON, EXPORT_FIGURE.

% A. M. Kaahin 2026-02-19
% Modified: 2026-06-01

    %% 1. Initialization
    if isfield(cfg, 'output') && isfield(cfg.output, 'fig_dir')
        fig_dir = cfg.output.fig_dir;
    else
        fig_dir = fullfile(pwd, 'results', 'figures');
    end

    filename = sprintf('partA_03_forecast_plot_%s.png', plot_name);
    outPath  = fullfile(fig_dir, filename);
    lead_time = local_plot_lead_time(cfg);

    y_limits = [];
    if isfield(cfg, 'Rt') && isfield(cfg.Rt, 'bounds')
        y_limits = cfg.Rt.bounds;
    end

    plot_alphas = [];
    if isfield(cfg, 'forecast') && isfield(cfg.forecast, 'plot_alphas')
        plot_alphas = cfg.forecast.plot_alphas;
    end

    plot_spec = build_plot_spec( ...
        'figure_name', "Forecast comparison", ...
        'title', sprintf('%d-Day-Ahead Forecast vs Truth: %s', ...
            lead_time, strrep(plot_name, '_', ' ')), ...
        'x_label', "Time (days)", ...
        'y_label', "$\mathcal{R}_t$", ...
        'output_path', outPath, ...
        'lead_time', lead_time, ...
        'plot_alphas', plot_alphas, ...
        'y_limits', y_limits, ...
        'legend', struct('truth_label', "Ground Truth", ...
        'median_label', sprintf('%d-Day-Ahead Median Forecast', lead_time), ...
        'location', "northwest"));

    truth_curve = struct('tspan', tspan, 'Rt_true', Rt_true);
    fig = plot_forecast_comparison(results, truth_curve, plot_spec);
    output_paths = export_figure(fig, plot_spec);
    close(fig);
    outPath = char(output_paths(1));
end

function lead_time = local_plot_lead_time(cfg)
%LOCAL_PLOT_LEAD_TIME Resolve legacy fixed lead time.
    lead_time = 7;
    if isfield(cfg, 'forecast') && isfield(cfg.forecast, 'plot_lead_time')
        lead_time = double(cfg.forecast.plot_lead_time);
    end

    if ~isscalar(lead_time) || ~isfinite(lead_time) || lead_time < 1
        error('PLOT:InvalidLeadTime', ...
            'Forecast plot lead time must be a positive scalar.');
    end

    lead_time = round(lead_time);
end
