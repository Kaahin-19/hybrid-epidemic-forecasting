%PARTA_01_GENERATE_TRUTH Compatibility entry point for Part A synthetic truth generation.
%
%   Description:
%       Delegates to the renamed Part A synthetic truth generation script.
%       This file is retained temporarily so existing run commands continue
%       to execute the refactored truth-generation stage.
%
%   Workflow:
%       1. Run the current Part A synthetic truth generation script.
%
%   See also PARTA_01_GENERATE_SYNTHETIC_TRUTH.
%
% A. M. Kaahin 2026-02-18
% Modified: 2026-05-31

%% 1. Delegate to Current Synthetic Truth Stage
run('scripts/partA/partA_01_generate_synthetic_truth.m');
