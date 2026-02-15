function Rt = rt_transient(t, p)
%RT_TRANSIENT Generate parametric transient reproduction number signals.
%
%   Syntax:
%       Rt = rt_transient(t, p)
%
%   Description:
%       Generates complex, non-periodic Rt trajectories based on a specific
%       morphology "kind" defined in the parameter structure. This function
%       is used to model policy interventions (steps) or epidemic resurgences
%       (waves).
%
%   Supported Kinds (p.kind):
%       1. "sigmoid_step" - Smooth transition (Sigmoid).
%          Models a policy intervention (e.g., Lockdown).
%          Formula: Rt = high + (low - high) / (1 + exp(-k * (t - t0)))
%          Params: .high, .low, .t0 (inflection point), .k (steepness).
%
%       2. "double_wave" - Double-peak Gaussian curves.
%          Models a resurgence or second wave.
%          Formula: Rt = baseline + Gauss(A1, mu1) + Gauss(A2, mu2)
%          Params: .baseline, .mu1/2 (centers), .A1/2 (heights), .denom (width).
%
%       3. "multi_wave" - Multi-peak Gaussian curves.
%          Models sustained damping or amplifying epidemic resurgences.
%          Formula: Rt = baseline + sum_{i=1}^{4} Gauss(Ai, mui)
%          Params: .baseline, .mu1/2/3/4 (centers), .A1/2/3/4 (heights), .denom (width).
%
%   Inputs:
%       t - Time vector [days].
%       p - Parameter structure. Must contain field .kind (string) plus the
%           specific parameters required by that kind (see above).
%
%   Outputs:
%       Rt - Vector of Rt values evaluated at t.
%
%   See also RT_SEASONAL, RT_TREND, PARTA_CONFIG.
    kind = string(p.kind);
    
    switch kind
        case "sigmoid_step"
            Rt = p.high + (p.low - p.high) ./ (1 + exp(-p.k * (t - p.t0)));
            
        case "double_wave"
            peak1 = p.A1 * exp(-((t - p.mu1).^2) / p.denom);
            peak2 = p.A2 * exp(-((t - p.mu2).^2) / p.denom);
            Rt = p.baseline + peak1 + peak2;
            
        case "multi_wave"
            peak1 = p.A1 * exp(-((t - p.mu1).^2) / p.denom);
            peak2 = p.A2 * exp(-((t - p.mu2).^2) / p.denom);
            peak3 = p.A3 * exp(-((t - p.mu3).^2) / p.denom);
            peak4 = p.A4 * exp(-((t - p.mu4).^2) / p.denom);
            Rt = p.baseline + peak1 + peak2 + peak3 + peak4;
            
        otherwise
            error("rt_transient:UnknownKind", ...
                "Unknown transient kind '%s'. Supported: 'sigmoid_step', 'double_wave', 'multi_wave'.", kind);
    end
    
end