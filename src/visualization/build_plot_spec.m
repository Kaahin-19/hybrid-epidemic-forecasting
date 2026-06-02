function plot_spec = build_plot_spec(varargin)
%BUILD_PLOT_SPEC Build a reusable plotting specification structure.
%
%   Syntax:
%       plot_spec = build_plot_spec()
%       plot_spec = build_plot_spec(name, value, ...)
%       plot_spec = build_plot_spec(existing_spec, name, value, ...)
%
%   Description:
%       Creates or updates a plot specification used by Part A visualization
%       helpers. The specification carries presentation choices such as
%       labels, titles, limits, figure size, legend text, and output paths so
%       plotting functions can focus on drawing data.
%
%   Inputs:
%       varargin - Optional structure followed by name-value pairs.
%
%   Outputs:
%       plot_spec - Structure of plotting options.
%
%   See also EXPORT_FIGURE.
%
% A. M. Kaahin 2026-06-01

    %% 1. Defaults
    plot_spec = struct();
    plot_spec.title = "";
    plot_spec.x_label = "";
    plot_spec.y_label = "";
    plot_spec.legend = struct();
    plot_spec.output_path = "";
    plot_spec.formats = "png";
    plot_spec.visible = "off";
    plot_spec.figure_name = "";
    plot_spec.size_cm = [17.0, 9.5];
    plot_spec.x_limits = [];
    plot_spec.y_limits = [];
    plot_spec.lead_time = [];
    plot_spec.plot_alphas = [];
    plot_spec.scenario_labels = strings(0, 1);
    plot_spec.resolution = 300;
    plot_spec.font_size = [];
    plot_spec.axis_label_font_size = [];
    plot_spec.tick_label_font_size = [];
    plot_spec.panel_labels = strings(0, 1);
    plot_spec.panel_label_style = struct();
    plot_spec.shared_x_label = "";
    plot_spec.shared_y_label = "";

    %% 2. Merge Inputs
    arg_idx = 1;
    if nargin >= 1 && isstruct(varargin{1})
        plot_spec = local_merge_struct(plot_spec, varargin{1});
        arg_idx = 2;
    end

    while arg_idx <= nargin
        if arg_idx == nargin
            error('PLOT:InvalidPlotSpec', ...
                'Plot specification name-value inputs must be paired.');
        end
        field_name = char(string(varargin{arg_idx}));
        plot_spec.(field_name) = varargin{arg_idx + 1};
        arg_idx = arg_idx + 2;
    end
end

function merged = local_merge_struct(base, override)
%LOCAL_MERGE_STRUCT Merge scalar structure fields.
    merged = base;
    fields = fieldnames(override);
    for i = 1:numel(fields)
        merged.(fields{i}) = override.(fields{i});
    end
end
