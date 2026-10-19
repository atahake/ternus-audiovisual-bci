function [pMotion, pC1Mean] = computeRespDistrib_AVTernus_v4(phiFull, param)
% computeRespDistrib_AVTernus_v4
% Motion-response observer for the audiovisual Ternus BCI analysis.
%
% Parameters:
%   phiFull = [pCommon, muP, sigP, sigA, sigV, criterion]
%
% Model codes:
%   1 = Bayesian causal inference with model averaging
%   4 = exact forced fusion      (C=1 with probability 1)
%   5 = exact segregation       (C=2 with probability 1)
%
% Input param fields:
%   iModel, taskName, sA, sV, xAPre, xVPre
%
% Output:
%   pMotion : nCondition x 2, columns = [P(element), P(group)]
%   pC1Mean : nCondition x 1, mean posterior P(C=1) across simulations
%
% This v4 core model intentionally fits MOTION responses only. Explicit
% common/separate responses are analyzed behaviorally first. A joint
% motion+causal likelihood will only be added after model/parameter recovery.

    validateattributes(phiFull, {'numeric'}, {'vector','numel',6,'real','finite'});
    phiFull = double(phiFull(:)');

    pCommon   = phiFull(1);
    muP       = phiFull(2);
    sigP      = phiFull(3);
    sigA      = phiFull(4);
    sigV      = phiFull(5);
    criterion = phiFull(6);

    if sigP <= 0 || sigA <= 0 || sigV <= 0
        error('sigP, sigA and sigV must be positive.');
    end
    if ~isfield(param,'iModel') || ~isfield(param,'taskName') || ...
       ~isfield(param,'sA') || ~isfield(param,'sV') || ...
       ~isfield(param,'xAPre') || ~isfield(param,'xVPre')
        error('param is missing required fields.');
    end
    if ~isequal(size(param.sA),size(param.sV),size(param.xAPre),size(param.xVPre))
        error('sA, sV, xAPre and xVPre must have identical sizes.');
    end

    sA = double(param.sA);
    sV = double(param.sV);
    xA = double(param.xAPre) .* sigA + sA;
    xV = double(param.xVPre) .* sigV + sV;

    varA = sigA^2;
    varV = sigV^2;
    varP = sigP^2;

    % Estimates under a common cause and under separate causes.
    sHatC1 = (xV./varV + xA./varA + muP./varP) ./ ...
             (1./varV + 1./varA + 1./varP);
    sHatAC2 = (xA./varA + muP./varP) ./ (1./varA + 1./varP);
    sHatVC2 = (xV./varV + muP./varP) ./ (1./varV + 1./varP);

    switch param.iModel
        case 1
            % Bayesian causal inference / model averaging.
            det1 = varV*varA + varV*varP + varA*varP;
            det2 = (varV+varP) * (varA+varP);

            quad1 = ((xV-xA).^2 .* varP + ...
                     (xV-muP).^2 .* varA + ...
                     (xA-muP).^2 .* varV) ./ det1;
            quad2 = (xV-muP).^2 ./ (varV+varP) + ...
                    (xA-muP).^2 ./ (varA+varP);

            logC1 = -log(2*pi) - 0.5*log(det1) - 0.5*quad1;
            logC2 = -log(2*pi) - 0.5*log(det2) - 0.5*quad2;

            pCommonSafe = min(max(pCommon,1e-8),1-1e-8);
            logOddsC2overC1 = logC2 + log(1-pCommonSafe) ...
                            - logC1 - log(pCommonSafe);
            logOddsC2overC1 = min(max(logOddsC2overC1,-700),700);
            pC1 = 1 ./ (1 + exp(logOddsC2overC1));

            sHatA = pC1 .* sHatC1 + (1-pC1) .* sHatAC2;
            sHatV = pC1 .* sHatC1 + (1-pC1) .* sHatVC2;

        case 4
            % Exact forced fusion.
            pC1 = ones(size(xA));
            sHatA = sHatC1;
            sHatV = sHatC1;

        case 5
            % Exact segregation.
            pC1 = zeros(size(xA));
            sHatA = sHatAC2;
            sHatV = sHatVC2;

        otherwise
            error('Unknown model code: %d', param.iModel);
    end

    if strcmpi(param.taskName,'Attend_A') || strcmpi(param.taskName,'AttendA')
        sHatTarget = sHatA;
    else
        sHatTarget = sHatV;
    end

    nSim = size(sHatTarget,2);
    if nSim < 1, error('No simulation samples supplied.'); end

    nGroup = sum(sHatTarget >= criterion,2);
    % Finite-simulation smoothing prevents exactly 0 or 1 probabilities.
    pGroup = (nGroup + 1) ./ (nSim + 2);
    pMotion = [1-pGroup, pGroup];
    pC1Mean = mean(pC1,2);
end
