function output_paths = export_figure(fig, plot_spec)
%EXPORT_FIGURE Export a figure according to a plot specification.
%
%   Syntax:
%       output_paths = export_figure(fig, plot_spec)
%
%   Description:
%       Centralizes Part A figure export behavior. If plot_spec.output_path
%       includes a file extension, that file is written directly. Otherwise,
%       the formats listed in plot_spec.formats are appended to the output
%       path stem.
%
%   Inputs:
%       fig       - Figure handle to export.
%       plot_spec - Plot specification with output_path, formats, resolution.
%
%   Outputs:
%       output_paths - String vector of written figure paths.
%
%   See also BUILD_PLOT_SPEC.
%
% A. M. Kaahin 2026-06-01

    %% 1. Input Validation
    if nargin < 2 || ~isstruct(plot_spec) || ~isfield(plot_spec, 'output_path') || ...
            strlength(string(plot_spec.output_path)) == 0
        error('PLOT:MissingOutputPath', ...
            'plot_spec.output_path is required for figure export.');
    end

    output_path = char(string(plot_spec.output_path));
    resolution = 300;
    if isfield(plot_spec, 'resolution') && ~isempty(plot_spec.resolution)
        resolution = double(plot_spec.resolution);
    end

    %% 2. Resolve Output Paths
    [output_dir, output_name, output_ext] = fileparts(output_path);
    if isempty(output_dir)
        output_dir = pwd;
    end
    if exist(output_dir, 'dir') ~= 7
        mkdir(output_dir);
    end

    if ~isempty(output_ext)
        output_paths = string(fullfile(output_dir, [output_name, output_ext]));
    else
        formats = string(plot_spec.formats);
        output_paths = strings(numel(formats), 1);
        for i = 1:numel(formats)
            fmt = erase(formats(i), ".");
            output_paths(i) = string(fullfile(output_dir, ...
                sprintf('%s.%s', output_name, char(fmt))));
        end
    end

    %% 3. Export
    for i = 1:numel(output_paths)
        exportgraphics(fig, output_paths(i), 'Resolution', resolution);
    end
end
