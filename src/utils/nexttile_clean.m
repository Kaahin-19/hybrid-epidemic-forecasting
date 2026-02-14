function ax = nexttile_clean(varargin)
%NEXTTILE_CLEAN Create a tile axes with UI interactivity disabled.
%
%   ax = nexttile_clean() is a thin wrapper around nexttile that ensures
%   exported figures never capture axes toolbars / hover UI.

    ax = nexttile(varargin{:});

    % Prevent axes toolbar from appearing in exported image
    ax.Toolbar = [];

    % Disable hover-driven interactivity overlays (zoom/pan UI hints, etc.)
    disableDefaultInteractivity(ax);
end