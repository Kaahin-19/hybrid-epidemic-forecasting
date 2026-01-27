%STARTUP Startup for HybridEpiPredict.

% S. Engblom 2026-01-27

% link = location of this startup.m
link = mfilename('fullpath');
link = link(1:end-numel(mfilename));

% path to folders
addpath(genpath([link 'data/']));
addpath(genpath([link 'sandbox/']));
addpath(genpath([link 'URDME/']));
