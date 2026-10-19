%% plot_baseline_psychometric_curves.m
% Plot individual baseline psychometric functions for all participants.
%
% This version keeps only commonly reported psychometric quantities:
%   PSE, JND, slope, endpoint error, residual deviance, deviance GOF p,
%   and a proportion-level R^2 for the fitted psychometric curve.
%
% Response coding:
%   group = 1
%   elem  = 0
%
% Psychometric model:
%   P(group) = logistic(b0 + b1 * ISI)
%   PSE = -b0 / b1
%   JND = log(3) / |b1|
%
% Goodness of fit:
%   Residual deviance
%   Deviance GOF p-value using df = number of ISI levels - 2
%   R^2 = 1 - SSE/SST across the empirical proportions at the ISI levels
%
% Required toolbox:
%   Statistics and Machine Learning Toolbox
%
% -------------------------------------------------------------------------

clear; clc; close all;

%% ========================== Paths ==========================
dataDir = 'C:\MSI\oscillation\ternus AV BCI\Data0714\Data';
analysisRoot = 'C:\MSI\oscillation\ternus AV BCI\analysis0906';
outDir = fullfile(analysisRoot, 'Baseline_Psychometric_Curves');

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

summaryFile = fullfile(outDir, 'Baseline_Psychometric_Summary.csv');
reportFile  = fullfile(outDir, 'Baseline_Psychometric_Report.txt');

if exist(reportFile, 'file')
    delete(reportFile);
end
diary(reportFile);
diary on;
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('============================================================\n');
fprintf(' Individual baseline psychometric curves\n');
fprintf(' Data:   %s\n', dataDir);
fprintf(' Output: %s\n', outDir);
fprintf(' Started: %s\n', datestr(now));
fprintf('============================================================\n\n');

%% ===================== Discover baseline files =====================
files = dir(fullfile(dataDir, '*_Block0_*_Complete.mat'));

if isempty(files)
    error('No *_Block0_*_Complete.mat files found in: %s', dataDir);
end

fprintf('Baseline Complete files found: %d\n', numel(files));

subjectIDs = strings(numel(files),1);
for i = 1:numel(files)
    tok = regexp(files(i).name, '^(.*?)_Block0_', 'tokens', 'once');
    if isempty(tok)
        error('Cannot parse subject ID from file name: %s', files(i).name);
    end
    subjectIDs(i) = string(tok{1});
end

uniqueIDs = unique(subjectIDs, 'stable');
fprintf('Unique participants with baseline files: %d\n\n', numel(uniqueIDs));

%% ===================== Select one baseline file per subject =====================
selectedFiles = repmat(files(1), numel(uniqueIDs), 1);
selectedFileNames = strings(numel(uniqueIDs),1);

for s = 1:numel(uniqueIDs)
    sid = uniqueIDs(s);
    idx = find(subjectIDs == sid);

    if numel(idx) == 1
        selectedFiles(s) = files(idx);
        selectedFileNames(s) = string(files(idx).name);
        continue;
    end

    bestIdx = idx(end);
    bestTime = -Inf;

    for k = 1:numel(idx)
        fpath = fullfile(files(idx(k)).folder, files(idx(k)).name);
        try
            tmp = load(fpath, 'P');
            if isfield(tmp, 'P') && isfield(tmp.P, 'startTime')
                t = datenum(tmp.P.startTime);
            else
                t = files(idx(k)).datenum;
            end
        catch
            t = files(idx(k)).datenum;
        end

        if t > bestTime
            bestTime = t;
            bestIdx = idx(k);
        end
    end

    selectedFiles(s) = files(bestIdx);
    selectedFileNames(s) = string(files(bestIdx).name);
    fprintf('Duplicate baseline files for %s -> selected %s\n', sid, files(bestIdx).name);
end

%% ===================== Analyze every participant =====================
nSubj = numel(uniqueIDs);

ID = strings(nSubj,1);
File = strings(nSubj,1);

N_V = zeros(nSubj,1);
N_A = zeros(nSubj,1);

V_PSE = nan(nSubj,1);
V_JND = nan(nSubj,1);
V_EdgeError = nan(nSubj,1);
V_Slope = nan(nSubj,1);
V_Deviance = nan(nSubj,1);
V_GOF_p = nan(nSubj,1);
V_R2 = nan(nSubj,1);
V_FitOK = false(nSubj,1);

A_PSE = nan(nSubj,1);
A_JND = nan(nSubj,1);
A_EdgeError = nan(nSubj,1);
A_Slope = nan(nSubj,1);
A_Deviance = nan(nSubj,1);
A_GOF_p = nan(nSubj,1);
A_R2 = nan(nSubj,1);
A_FitOK = false(nSubj,1);

for s = 1:nSubj
    sid = uniqueIDs(s);
    ID(s) = sid;
    File(s) = selectedFileNames(s);

    fpath = fullfile(selectedFiles(s).folder, selectedFiles(s).name);
    fprintf('[%02d/%02d] %s -> %s\n', s, nSubj, sid, selectedFiles(s).name);

    S = load(fpath);
    if ~isfield(S, 'T') || ~istable(S.T)
        warning('%s does not contain table T. Skipped.', selectedFiles(s).name);
        continue;
    end

    T = S.T;
    required = {'Task','ISI_V','ISI_A','Resp_Motion'};
    if ~all(ismember(required, T.Properties.VariableNames))
        warning('%s is missing required baseline variables. Skipped.', sid);
        continue;
    end

    task = normalizeTextColumn(T.Task);
    respText = normalizeTextColumn(T.Resp_Motion);

    resp = nan(height(T),1);
    resp(respText == "group") = 1;
    resp(respText == "elem") = 0;

    isiV = double(T.ISI_V);
    isiA = double(T.ISI_A);

    idxV = task == "baseline_v" & isfinite(isiV) & isfinite(resp);
    idxA = task == "baseline_a" & isfinite(isiA) & isfinite(resp);

    xV = isiV(idxV);
    yV = resp(idxV);
    xA = isiA(idxA);
    yA = resp(idxA);

    N_V(s) = numel(yV);
    N_A(s) = numel(yA);

    fitV = fitPsychometric(xV, yV);
    fitA = fitPsychometric(xA, yA);

    if fitV.ok
        V_PSE(s) = fitV.PSE;
        V_JND(s) = fitV.JND;
        V_EdgeError(s) = fitV.edgeError;
        V_Slope(s) = fitV.slope;
        V_Deviance(s) = fitV.deviance;
        V_GOF_p(s) = fitV.gofP;
        V_R2(s) = fitV.R2;
        V_FitOK(s) = true;
    end

    if fitA.ok
        A_PSE(s) = fitA.PSE;
        A_JND(s) = fitA.JND;
        A_EdgeError(s) = fitA.edgeError;
        A_Slope(s) = fitA.slope;
        A_Deviance(s) = fitA.deviance;
        A_GOF_p(s) = fitA.gofP;
        A_R2(s) = fitA.R2;
        A_FitOK(s) = true;
    end

    %% ------------------- Figure -------------------
    fig = figure('Color','w', ...
        'Name', char(sid), ...
        'Position', [100 100 1100 470], ...
        'Visible', 'off');

    subplot(1,2,1);
    plotPsychometricPanel(fitV, 'Visual baseline');

    subplot(1,2,2);
    plotPsychometricPanel(fitA, 'Auditory baseline');

    try
        sgtitle(sprintf('%s | Baseline Ternus psychometric functions', char(sid)), ...
            'Interpreter','none', 'FontWeight','bold');
    catch
    end

    pngPath = fullfile(outDir, sprintf('%s_Baseline_Psychometric.png', char(sid)));
    try
        exportgraphics(fig, pngPath, 'Resolution', 220);
    catch
        saveas(fig, pngPath);
    end
    close(fig);
end

%% ===================== Save summary =====================
summaryTable = table( ...
    cellstr(ID), cellstr(File), ...
    N_V, V_PSE, V_JND, V_EdgeError, V_Slope, V_Deviance, V_GOF_p, V_R2, V_FitOK, ...
    N_A, A_PSE, A_JND, A_EdgeError, A_Slope, A_Deviance, A_GOF_p, A_R2, A_FitOK, ...
    'VariableNames', { ...
    'ID','BaselineFile', ...
    'N_Visual','V_PSE','V_JND','V_EdgeError','V_Slope','V_Deviance','V_GOF_p','V_R2','V_FitOK', ...
    'N_Auditory','A_PSE','A_JND','A_EdgeError','A_Slope','A_Deviance','A_GOF_p','A_R2','A_FitOK'});

writetable(summaryTable, summaryFile);

%% ===================== Print GOF flags =====================
fprintf('\n---------------- GOF flags ----------------\n');

vFlag = V_FitOK & isfinite(V_GOF_p) & V_GOF_p < 0.05;
aFlag = A_FitOK & isfinite(A_GOF_p) & A_GOF_p < 0.05;

if any(vFlag)
    fprintf('Visual baseline: GOF p < .05:\n');
    disp(summaryTable(vFlag, {'ID','V_PSE','V_JND','V_Deviance','V_GOF_p','V_R2','V_EdgeError'}));
else
    fprintf('Visual baseline: no fitted participant has GOF p < .05.\n');
end

if any(aFlag)
    fprintf('Auditory baseline: GOF p < .05:\n');
    disp(summaryTable(aFlag, {'ID','A_PSE','A_JND','A_Deviance','A_GOF_p','A_R2','A_EdgeError'}));
else
    fprintf('Auditory baseline: no fitted participant has GOF p < .05.\n');
end

fprintf('\n============================================================\n');
fprintf('Finished.\n');
fprintf('Participants plotted: %d\n', nSubj);
fprintf('Visual fits OK:   %d / %d\n', sum(V_FitOK), nSubj);
fprintf('Auditory fits OK: %d / %d\n', sum(A_FitOK), nSubj);
fprintf('Visual GOF p < .05: %d\n', sum(vFlag));
fprintf('Auditory GOF p < .05: %d\n', sum(aFlag));
fprintf('Figures folder:\n  %s\n', outDir);
fprintf('Summary CSV:\n  %s\n', summaryFile);
fprintf('Report:\n  %s\n', reportFile);
fprintf('Finished: %s\n', datestr(now));
fprintf('============================================================\n');

diary off;

%% ========================================================================
% Local functions
% ========================================================================

function fit = fitPsychometric(ISI, Resp)
    fit = struct();
    fit.ok = false;

    fit.PSE = NaN;
    fit.JND = NaN;
    fit.edgeError = NaN;
    fit.slope = NaN;
    fit.intercept = NaN;
    fit.deviance = NaN;
    fit.gofP = NaN;
    fit.R2 = NaN;

    fit.levels = [];
    fit.propGroup = [];
    fit.xFine = [];
    fit.pFine = [];

    ISI = double(ISI(:));
    Resp = double(Resp(:));

    valid = isfinite(ISI) & isfinite(Resp) & ismember(Resp,[0 1]);
    ISI = ISI(valid);
    Resp = Resp(valid);

    if numel(ISI) < 10 || numel(unique(ISI)) < 3
        return;
    end

    levels = unique(ISI);
    nLev = numel(levels);
    Y = zeros(nLev,1);
    N = zeros(nLev,1);

    for i = 1:nLev
        idx = ISI == levels(i);
        Y(i) = sum(Resp(idx) == 1);
        N(i) = sum(idx);
    end

    prop = Y ./ N;

    fit.levels = levels;
    fit.propGroup = prop;
    fit.edgeError = (prop(1) + (1 - prop(end))) / 2;

    oldWarn = warning;
    cleanupWarn = onCleanup(@() warning(oldWarn)); %#ok<NASGU>
    warning('off', 'stats:glmfit:PerfectSeparation');
    warning('off', 'stats:glmfit:IterationLimit');

    try
        [b, dev] = glmfit(levels, [Y N], 'binomial', 'link', 'logit');

        if numel(b) < 2 || ~all(isfinite(b)) || abs(b(2)) < eps
            return;
        end

        fit.intercept = b(1);
        fit.slope = b(2);
        fit.PSE = -b(1) / b(2);
        fit.JND = log(3) / abs(b(2));

        fit.xFine = linspace(min(levels), max(levels), 500)';
        fit.pFine = 1 ./ (1 + exp(-(b(1) + b(2) * fit.xFine)));

        fit.deviance = dev;
        gofDF = nLev - 2;
        if gofDF > 0 && isfinite(dev)
            fit.gofP = 1 - chi2cdf(dev, gofDF);
        end

        % Proportion-level R^2 across the seven ISI levels.
        % This is the ordinary coefficient of determination between the
        % empirical P(group) values and the fitted logistic probabilities.
        pHatLevels = 1 ./ (1 + exp(-(b(1) + b(2) * levels)));
        sse = sum((prop - pHatLevels).^2);
        sst = sum((prop - mean(prop)).^2);
        if sst > eps
            fit.R2 = 1 - sse / sst;
        end

        fit.ok = isfinite(fit.PSE) && isfinite(fit.JND) && ...
                 fit.JND > 0 && all(isfinite(fit.pFine));

    catch ME
        warning('Psychometric fit failed: %s', ME.message);
        fit.ok = false;
    end
end

function plotPsychometricPanel(fit, panelTitle)
    hold on;

    if isempty(fit.levels)
        text(0.5,0.5,'No valid baseline trials', ...
            'Units','normalized','HorizontalAlignment','center');
        title(panelTitle);
        ylim([0 1]);
        box off;
        return;
    end

    plot(fit.levels, fit.propGroup, 'o', ...
        'MarkerSize', 7, ...
        'LineWidth', 1.2, ...
        'MarkerFaceColor', 'w');

    if fit.ok
        plot(fit.xFine, fit.pFine, '-', 'LineWidth', 2);

        yline(0.5, '--');
        xline(fit.PSE, '--');

        txt = sprintf([ ...
            'PSE = %.1f ms\n' ...
            'JND = %.1f ms\n' ...
            'Slope = %.4f\n' ...
            'Edge error = %.3f\n' ...
            'Deviance = %.2f\n' ...
            'GOF p = %.4f\n' ...
            'R^2 = %.3f'], ...
            fit.PSE, fit.JND, fit.slope, fit.edgeError, ...
            fit.deviance, fit.gofP, fit.R2);
    else
        txt = sprintf('Fit failed\nEdge error = %.3f', fit.edgeError);
    end

    text(0.04, 0.96, txt, ...
        'Units','normalized', ...
        'VerticalAlignment','top', ...
        'BackgroundColor','w', ...
        'Margin',5, ...
        'FontSize',9);

    xlabel('ISI (ms)');
    ylabel('P(group motion)');
    title(panelTitle);
    ylim([-0.03 1.03]);

    if numel(fit.levels) > 1
        xlim([min(fit.levels)-10, max(fit.levels)+10]);
        xticks(fit.levels);
    end

    grid on;
    box off;
end

function sx = normalizeTextColumn(x)
    if isstring(x)
        sx = x(:);
    elseif iscategorical(x)
        sx = string(x(:));
    elseif ischar(x)
        if isrow(x)
            sx = string({x});
        else
            sx = string(cellstr(x));
        end
        sx = sx(:);
    elseif iscell(x)
        sx = strings(numel(x), 1);

        for ii = 1:numel(x)
            value = x{ii};

            while iscell(value) && isscalar(value)
                value = value{1};
            end

            if isempty(value)
                continue;
            elseif isstring(value)
                tmp = value(:);
                tmp = tmp(~ismissing(tmp) & strlength(tmp) > 0);
                if ~isempty(tmp), sx(ii) = tmp(1); end
            elseif ischar(value)
                sx(ii) = string(value);
            elseif iscategorical(value)
                tmp = string(value(:));
                tmp = tmp(~ismissing(tmp) & strlength(tmp) > 0);
                if ~isempty(tmp), sx(ii) = tmp(1); end
            elseif isnumeric(value) || islogical(value)
                if isscalar(value) && isfinite(double(value))
                    sx(ii) = string(value);
                end
            else
                try
                    tmp = string(value);
                    tmp = tmp(:);
                    tmp = tmp(~ismissing(tmp) & strlength(tmp) > 0);
                    if ~isempty(tmp), sx(ii) = tmp(1); end
                catch
                end
            end
        end
    else
        sx = string(x(:));
    end

    sx = lower(strtrim(sx));
end
