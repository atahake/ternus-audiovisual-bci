function negLL = computeNegLL_AVTernus_v4(phiFree, param)
% computeNegLL_AVTernus_v4
% Aggregated binomial negative log likelihood for v4 Ternus BCI models.
%
% Required param fields:
%   fixedPhi  : 1x6 full parameter template
%   freeMask  : 1x6 logical mask
%   dataCounts: nCondition x 2 [nElement, nGroup]
% plus fields required by computeRespDistrib_AVTernus_v4.

    try
        if ~isfield(param,'fixedPhi') || ~isfield(param,'freeMask') || ...
           ~isfield(param,'dataCounts')
            error('param is missing fixedPhi/freeMask/dataCounts.');
        end

        phiFull = double(param.fixedPhi(:)');
        freeMask = logical(param.freeMask(:)');
        phiFull(freeMask) = double(phiFree(:)');

        [pMotion, ~] = computeRespDistrib_AVTernus_v4(phiFull,param);
        pMotion = min(max(pMotion,realmin('double')),1-realmin('double'));
        pMotion = pMotion ./ sum(pMotion,2);

        counts = double(param.dataCounts);
        if size(counts,2) ~= 2 || size(counts,1) ~= size(pMotion,1)
            error('dataCounts must be nCondition x 2 and match predictions.');
        end
        if any(counts(:) < 0) || any(~isfinite(counts(:)))
            error('Invalid response counts.');
        end

        n  = sum(counts,2);
        k0 = counts(:,1);
        k1 = counts(:,2);

        % Exact aggregated binomial log likelihood. The combinatorial term
        % is retained so the reported LL is a true likelihood value.
        ll = gammaln(n+1) - gammaln(k0+1) - gammaln(k1+1) + ...
             k0 .* log(pMotion(:,1)) + k1 .* log(pMotion(:,2));

        negLL = -sum(ll);
    catch ME
        % Optimizers must receive a finite penalty rather than crash.
        % Uncomment the next line for debugging if needed:
        % warning('computeNegLL_AVTernus_v4:%s', ME.message);
        negLL = 1e12;
    end

    if ~isscalar(negLL) || ~isfinite(negLL) || ~isreal(negLL)
        negLL = 1e12;
    end
end
