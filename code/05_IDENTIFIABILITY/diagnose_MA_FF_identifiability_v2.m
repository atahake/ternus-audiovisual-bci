%% diagnose_MA_FF_identifiability.m
% Fast diagnostic follow-up for the audiovisual Ternus BCI analysis.
%
% PURPOSE
% -------
% 1) Diagnose why Model Averaging (MA) synthetic datasets are often recovered
%    as Forced Fusion (FF).
% 2) Quantify observable MA-vs-FF prediction overlap on the actual 7x7 grid.
% 3) Separate likelihood advantage from BIC complexity penalty.
% 4) Validate model sensory-noise parameters against independent baseline JND.
% 5) Test exploratory disparity x baseline-reliability effects.
% 6) Audit raw MAT metadata for WFI/IFI/refresh/reliability setting fields.
%
% IMPORTANT
% ---------
% - This script does NOT delete conditions.
% - It does NOT change the R^2 cutoff.
% - It does NOT refit the full model recovery by default.
% - It uses the existing Phase2 results and caches.
%
% Dependency:
%   computeRespDistrib_AVTernus_v4.m
%   Statistics and Machine Learning Toolbox
%
% -------------------------------------------------------------------------

clear; clc; close all;

%% ========================== PATHS =====================================
ANALYSIS_ROOT = 'C:\MSI\oscillation\ternus AV BCI\analysis0906';
SCRIPT_DIR = fullfile(ANALYSIS_ROOT,'analysis');
PHASE2_DIR = fullfile(ANALYSIS_ROOT,'Analysis_Output_v4_R2_070');
PHASE2_MAT = fullfile(PHASE2_DIR,'Phase2_Analysis_Results_v4.mat');
DIAG_DIR = fullfile(PHASE2_DIR,'MA_FF_Identifiability_Diagnostics');

if ~exist(DIAG_DIR,'dir'), mkdir(DIAG_DIR); end
if ~exist(PHASE2_MAT,'file')
    error('Cannot find Phase2 results: %s',PHASE2_MAT);
end

addpath(SCRIPT_DIR);

if exist('computeRespDistrib_AVTernus_v4','file')~=2
    error('computeRespDistrib_AVTernus_v4.m must be on the MATLAB path.');
end

%% ========================== SETTINGS =================================
N_SIM_PRED = 12000;             % prediction-overlap Monte Carlo samples
BOUNDARY_TOL_FRAC = 0.02;       % within 2%% of parameter range = near boundary
RUN_METADATA_AUDIT = true;
RUN_RELIABILITY_ANALYSIS = true;

% Heavy re-fitting is intentionally not part of this first diagnostic pass.
% After reading these outputs, decide whether to run optimization-stability
% and trial-count recovery checks.

summaryPath = fullfile(DIAG_DIR,'Diagnostic_Summary.txt');
if exist(summaryPath,'file'), delete(summaryPath); end
diary(summaryPath);
diary on;
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('=====================================================================\n');
fprintf(' Ternus BCI: MA -> FF identifiability + reliability diagnostics\n');
fprintf(' Started: %s\n',datestr(now));
fprintf(' Phase2: %s\n',PHASE2_MAT);
fprintf(' Output: %s\n',DIAG_DIR);
fprintf('=====================================================================\n\n');

%% ========================== LOAD =====================================
fprintf('[1/7] Loading existing Phase-2 results...\n');
S = load(PHASE2_MAT,'fileAudit','qualityTable','trialTable','bciFits', ...
    'recoveryFits','recoveryWinners','recoveryConfusion','bciEvidence');

requiredVars = {'fileAudit','qualityTable','trialTable','bciFits','recoveryFits','recoveryWinners'};
for i=1:numel(requiredVars)
    if ~isfield(S,requiredVars{i})
        error('Phase2 MAT is missing %s.',requiredVars{i});
    end
end

fileAudit = S.fileAudit;
q = S.qualityTable;
trials = S.trialTable;
bciFits = S.bciFits;
recoveryFits = S.recoveryFits;
recoveryWinners = S.recoveryWinners;

if ~ismember('R2PrimaryIncluded',q.Properties.VariableNames)
    error('qualityTable does not contain R2PrimaryIncluded.');
end

primaryIDs = string(q.ID(q.R2PrimaryIncluded));
fprintf('Primary R2-filtered participants: N = %d\n\n',numel(primaryIDs));

%% ===================== 2. RELIABILITY TABLE ==========================
fprintf('[2/7] Building independent baseline reliability proxies...\n');

qr = q(q.R2PrimaryIncluded,:);
rel = table();
rel.Subject = string(qr.ID);
rel.JND_A = qr.A_JND;
rel.JND_V = qr.V_JND;
rel.Precision_A = 1 ./ (rel.JND_A.^2);
rel.Precision_V = 1 ./ (rel.JND_V.^2);
rel.LogPrecision_A = log(rel.Precision_A);
rel.LogPrecision_V = log(rel.Precision_V);
rel.LogRelRatio_AoverV = log(rel.Precision_A ./ rel.Precision_V);
rel.JointJNDProxy = sqrt(rel.JND_A.^2 + rel.JND_V.^2);
rel.JointPrecisionProxy = 1 ./ (rel.JND_A.^2 + rel.JND_V.^2);
rel.LogJointPrecision = log(rel.JointPrecisionProxy);
rel.LogJointPrecisionC = rel.LogJointPrecision - mean(rel.LogJointPrecision,'omitnan');

writetable(rel,fullfile(DIAG_DIR,'Baseline_Reliability_Proxies.csv'));

fprintf('Median JND_A = %.3f ms; median JND_V = %.3f ms\n', ...
    median(rel.JND_A,'omitnan'),median(rel.JND_V,'omitnan'));
fprintf('Median precision ratio A/V = %.3f\n\n', ...
    median(rel.Precision_A./rel.Precision_V,'omitnan'));

%% ================= 3. MA-GENERATED RECOVERY DIAGNOSTICS ==============
fprintf('[3/7] Diagnosing MA-generated recovery outcomes...\n');

maRec = buildMAGeneratedDiagnostics(recoveryFits,recoveryWinners,rel);
writetable(maRec,fullfile(DIAG_DIR,'MA_Generated_MA_vs_FF_Diagnostics.csv'));

tasks = ["AttendV","AttendA"];
recSummaryRows = cell(0,9);

for it=1:numel(tasks)
    x = maRec(string(maRec.Task)==tasks(it),:);
    if isempty(x), continue; end

    n = height(x);
    nFF = sum(x.FFWin);
    nMA = sum(x.MAWin);
    nPenalty = sum(x.PenaltyReversal);
    medDBIC = median(x.DeltaBIC_MAminusFF,'omitnan');
    medDLL = median(x.DeltaLL_MAminusFF,'omitnan');

    % Univariate diagnostic logistic regressions.
    [bPC,pPC] = logisticDiagnostic(x.True_pCommon,x.FFWin);
    [bJS,pJS] = logisticDiagnostic(log(x.TrueJointSigma),x.FFWin);

    recSummaryRows(end+1,:) = {char(tasks(it)),n,nMA,nFF,nPenalty, ...
        nPenalty/max(n,1),medDLL,medDBIC,bPC}; %#ok<AGROW>

    fprintf('%s: MA-generated N=%d | recovered MA=%d | recovered FF=%d\n', ...
        tasks(it),n,nMA,nFF);
    fprintf('  Complexity-penalty reversals (LL favors MA but BIC favors FF): %d/%d (%.1f%%)\n', ...
        nPenalty,n,100*nPenalty/max(n,1));
    fprintf('  Median DeltaLL(MA-FF)=%.4f; Median DeltaBIC(MA-FF)=%.4f\n',medDLL,medDBIC);
    fprintf('  FFWin ~ True_pCommon: beta=%.4f, p=%.4g\n',bPC,pPC);
    fprintf('  FFWin ~ log(TrueJointSigma): beta=%.4f, p=%.4g\n\n',bJS,pJS);
end

recSummary = cell2table(recSummaryRows,'VariableNames', ...
    {'Task','N','NRecoveredMA','NRecoveredFF','NPenaltyReversal', ...
     'PenaltyReversalProportion','MedianDeltaLL_MAminusFF', ...
     'MedianDeltaBIC_MAminusFF','FFWinBeta_TruePCommon'});
writetable(recSummary,fullfile(DIAG_DIR,'MA_Generated_Recovery_Summary.csv'));

fig = figure('Color','w','Position',[100 100 1050 430]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
for it=1:numel(tasks)
    nexttile; hold on;
    x=maRec(string(maRec.Task)==tasks(it),:);
    if isempty(x), continue; end
    jitter=(rand(height(x),1)-0.5)*0.08;
    y=double(x.FFWin);
    scatter(x.True_pCommon,y+jitter,42,'filled');
    yline(0.5,'--');
    xlabel('Generating pCommon');
    ylabel('Recovered as FF (1=yes)');
    title(sprintf('%s: MA-generated datasets',tasks(it)));
    ylim([-0.15 1.15]); grid on; box off;
end
saveFigure(fig,fullfile(DIAG_DIR,'Figure_MA_to_FF_Diagnostics.png'));
close(fig);

%% ================= 4. MA-vs-FF PREDICTION OVERLAP ====================
fprintf('[4/7] Computing MA-vs-FF prediction overlap on the actual 7x7 grid...\n');
fprintf('      N_SIM_PRED = %d per condition\n',N_SIM_PRED);

[overlapBySubject,overlapCells] = computePredictionOverlap( ...
    trials,q,bciFits,primaryIDs,N_SIM_PRED);

writetable(overlapBySubject,fullfile(DIAG_DIR,'MA_FF_Prediction_Overlap_BySubject.csv'));
writetable(overlapCells,fullfile(DIAG_DIR,'MA_FF_Prediction_Overlap_ByCell.csv'));

% Merge recovery outcome so we can ask whether misclassified MA datasets
% occur in participants whose MA and FF predictions are especially similar.
ov = outerjoin(overlapBySubject,maRec(:,{'Subject','Task','FFWin','True_pCommon', ...
    'DeltaBIC_MAminusFF','DeltaLL_MAminusFF'}), ...
    'Keys',{'Subject','Task'},'MergeKeys',true,'Type','left');
writetable(ov,fullfile(DIAG_DIR,'MA_FF_Overlap_With_RecoveryOutcome.csv'));

for it=1:numel(tasks)
    x=ov(string(ov.Task)==tasks(it) & isfinite(ov.DeltaBIC_MAminusFF),:);
    if height(x)>=3
        [r1,p1]=corr(double(x.MeanAbsDeltaP_SameParams),double(x.DeltaBIC_MAminusFF), ...
            'Rows','complete','Type','Pearson');
        [r2,p2]=corr(double(x.MeanPC1_MA),double(x.DeltaBIC_MAminusFF), ...
            'Rows','complete','Type','Pearson');
        fprintf('%s overlap diagnostic:\n',tasks(it));
        fprintf('  Mean |DeltaP| same-params vs DeltaBIC(MA-FF): r=%.3f, p=%.4g\n',r1,p1);
        fprintf('  Mean posterior P(C=1) vs DeltaBIC(MA-FF): r=%.3f, p=%.4g\n',r2,p2);
        fprintf('  Mean |DeltaP| same-params = %.4f; best-fit = %.4f\n', ...
            mean(x.MeanAbsDeltaP_SameParams,'omitnan'),mean(x.MeanAbsDeltaP_BestFits,'omitnan'));
        fprintf('  Mean posterior P(C=1) across grid = %.4f\n\n',mean(x.MeanPC1_MA,'omitnan'));
    end
end

fig = plotOverlapHeatmaps(overlapCells);
saveFigure(fig,fullfile(DIAG_DIR,'Figure_MA_FF_Prediction_Overlap.png'));
close(fig);

%% ================= 5. PARAMETER-BOUNDARY DIAGNOSTICS =================
fprintf('[5/7] Checking fitted-parameter boundary pile-up...\n');
boundary = buildBoundaryDiagnostics(bciFits,recoveryFits,BOUNDARY_TOL_FRAC);
writetable(boundary,fullfile(DIAG_DIR,'Parameter_Boundary_Diagnostics.csv'));
disp(boundary);

%% ================= 6. RELIABILITY ANALYSIS ===========================
fprintf('[6/7] Testing baseline reliability against model parameters and AV behavior...\n');

if RUN_RELIABILITY_ANALYSIS
    relValidation = validateBaselineVsModelReliability(rel,bciFits);
    writetable(relValidation,fullfile(DIAG_DIR,'Baseline_vs_Model_Reliability_Validation.csv'));

    [causalModelComp,causalCoef] = runCausalReliabilityModels(trials,rel,primaryIDs);
    writetable(causalModelComp,fullfile(DIAG_DIR,'Reliability_Aware_Causal_Model_Comparison.csv'));
    writetable(causalCoef,fullfile(DIAG_DIR,'Reliability_Aware_Causal_Coefficients.csv'));

    [motionModelComp,motionCoef] = runMotionReliabilityModels(trials,rel,primaryIDs);
    writetable(motionModelComp,fullfile(DIAG_DIR,'Reliability_Aware_Motion_Model_Comparison.csv'));
    writetable(motionCoef,fullfile(DIAG_DIR,'Reliability_Aware_Motion_Coefficients.csv'));

    reliabilitySummary = buildReliabilitySummary(relValidation,causalModelComp,causalCoef,motionModelComp,motionCoef);
    writetable(reliabilitySummary,fullfile(DIAG_DIR,'Reliability_Analysis_Summary.csv'));

    fprintf('\nBaseline vs model reliability validation:\n');
    disp(relValidation);
    fprintf('\nCausal reliability model comparison:\n');
    disp(causalModelComp);
    fprintf('\nCausal reliability coefficients:\n');
    disp(causalCoef);
    fprintf('\nMotion reliability model comparison:\n');
    disp(motionModelComp);
    fprintf('\nMotion reliability coefficients:\n');
    disp(motionCoef);
else
    fprintf('Reliability analysis disabled.\n');
end

%% ================= 7. RAW METADATA / WFI AUDIT =======================
fprintf('[7/7] Auditing raw MAT metadata for WFI / IFI / reliability-setting fields...\n');

if RUN_METADATA_AUDIT
    [metaCandidates,metaSummary] = auditSettingMetadata(fileAudit);
    writetable(metaCandidates,fullfile(DIAG_DIR,'Metadata_Candidate_Settings.csv'));
    writetable(metaSummary,fullfile(DIAG_DIR,'Metadata_Candidate_Settings_Summary.csv'));

    fprintf('Candidate metadata entries found: %d\n',height(metaCandidates));
    if ~isempty(metaSummary)
        fprintf('Candidate field summary:\n');
        disp(metaSummary);
    else
        fprintf('No matching scalar/string setting fields were found in the selected MAT metadata.\n');
    end
else
    fprintf('Metadata audit disabled.\n');
end

fprintf('\n=====================================================================\n');
fprintf('FAST DIAGNOSTIC PASS FINISHED\n');
fprintf('Output folder:\n  %s\n',DIAG_DIR);
fprintf('\nPlease return these first:\n');
fprintf('  Diagnostic_Summary.txt\n');
fprintf('  MA_Generated_MA_vs_FF_Diagnostics.csv\n');
fprintf('  MA_FF_Prediction_Overlap_BySubject.csv\n');
fprintf('  Reliability_Analysis_Summary.csv\n');
fprintf('  Metadata_Candidate_Settings.csv\n');
fprintf('  Figure_MA_FF_Prediction_Overlap.png\n');
fprintf('  Figure_MA_to_FF_Diagnostics.png\n');
fprintf('Finished: %s\n',datestr(now));
fprintf('=====================================================================\n');

diary off;

%% ====================================================================
% LOCAL FUNCTIONS
% =====================================================================

function out=buildMAGeneratedDiagnostics(rf,rw,rel)
    ma=rf(string(rf.GeneratingModel)=="ModelAveraging",:);
    reps=unique(ma.CohortRep);
    tasks=unique(string(ma.Task),'stable');
    subjs=unique(string(ma.Subject),'stable');
    rows=cell(0,23);

    for ir=1:numel(reps)
        for it=1:numel(tasks)
            for is=1:numel(subjs)
                x=ma(ma.CohortRep==reps(ir) & string(ma.Task)==tasks(it) & ...
                    string(ma.Subject)==subjs(is),:);
                if isempty(x),continue;end
                rMA=x(string(x.FittedModel)=="ModelAveraging",:);
                rFF=x(string(x.FittedModel)=="ForcedFusion",:);
                if height(rMA)~=1 || height(rFF)~=1,continue;end

                w=rw(rw.CohortRep==reps(ir) & string(rw.Task)==tasks(it) & ...
                    string(rw.Subject)==subjs(is) & string(rw.GeneratingModel)=="ModelAveraging",:);
                winner="";
                if height(w)==1,winner=string(w.WinningModel);end

                rr=rel(rel.Subject==subjs(is),:);
                if isempty(rr)
                    jA=NaN;jV=NaN;logBaseRatio=NaN;logJointPrec=NaN;
                else
                    jA=rr.JND_A(1);jV=rr.JND_V(1);
                    logBaseRatio=rr.LogRelRatio_AoverV(1);
                    logJointPrec=rr.LogJointPrecision(1);
                end

                trueJointSigma=sqrt(rMA.True_sigA^2+rMA.True_sigV^2);
                trueLogRelRatio=log((1/rMA.True_sigA^2)/(1/rMA.True_sigV^2));
                dLL=rMA.LLK-rFF.LLK;
                dBIC=rMA.BIC-rFF.BIC;
                ffWin=winner=="ForcedFusion";
                maWin=winner=="ModelAveraging";
                penaltyReversal=(dLL>0)&&(dBIC>0);

                rows(end+1,:)={reps(ir),char(subjs(is)),char(tasks(it)),char(winner), ...
                    ffWin,maWin,rMA.True_pCommon,rMA.True_muP,rMA.True_sigP, ...
                    rMA.True_sigA,rMA.True_sigV,rMA.True_Criterion,trueJointSigma,trueLogRelRatio, ...
                    jA,jV,logBaseRatio,logJointPrec,rMA.LLK,rFF.LLK,dLL,dBIC,penaltyReversal}; %#ok<AGROW>
            end
        end
    end

    out=cell2table(rows,'VariableNames',{'CohortRep','Subject','Task','Winner', ...
        'FFWin','MAWin','True_pCommon','True_muP','True_sigP','True_sigA','True_sigV', ...
        'True_Criterion','TrueJointSigma','TrueLogRelRatio_AoverV', ...
        'Baseline_JND_A','Baseline_JND_V','BaselineLogRelRatio_AoverV','BaselineLogJointPrecision', ...
        'LL_MA','LL_FF','DeltaLL_MAminusFF','DeltaBIC_MAminusFF','PenaltyReversal'});
end

function [beta,p]=logisticDiagnostic(x,y)
    beta=NaN;p=NaN;
    valid=isfinite(x)&isfinite(y);
    x=x(valid);y=double(y(valid));
    if numel(x)<6 || numel(unique(y))<2,return;end
    x=(x-mean(x))/std(x);
    try
        [b,~,st]=glmfit(x,[y ones(size(y))],'binomial','link','logit');
        beta=b(2);p=st.p(2);
    catch
    end
end

function [bySub,byCell]=computePredictionOverlap(tbl,q,fits,ids,nSim)
    tasks=["AttendV","AttendA"];
    rowSub=cell(0,10);
    rowCell=cell(0,8);

    for it=1:numel(tasks)
        task=tasks(it);
        modelTask='Attend_V';
        if task=="AttendA",modelTask='Attend_A';end

        for is=1:numel(ids)
            sid=ids(is);
            qi=find(string(q.ID)==sid,1);
            if isempty(qi),continue;end

            d=tbl(string(tbl.Subject)==sid & string(tbl.Task)==task,:);
            d=d(isfinite(d.ISI_A)&isfinite(d.ISI_V)&isfinite(d.RespMotion),:);
            if isempty(d),continue;end

            nominal=[d.ISI_A,d.ISI_V];
            [uv,~,g]=unique(nominal,'rows');
            nCond=size(uv,1);
            sA=zeros(nCond,1);sV=zeros(nCond,1);nTrials=zeros(nCond,1);

            for c=1:nCond
                idx=g==c;
                sA(c)=mean(d.CenteredA(idx),'omitnan');
                sV(c)=mean(d.CenteredV(idx),'omitnan');
                nTrials(c)=sum(idx);
            end

            fMA=fits(string(fits.Subject)==sid & string(fits.Task)==task & ...
                string(fits.Model)=="ModelAveraging" & string(fits.Coordinate)=="pse_centered",:);
            fFF=fits(string(fits.Subject)==sid & string(fits.Task)==task & ...
                string(fits.Model)=="ForcedFusion" & string(fits.Coordinate)=="pse_centered",:);
            if height(fMA)~=1 || height(fFF)~=1,continue;end

            phiMA=[fMA.pCommon fMA.muP fMA.sigP fMA.sigA fMA.sigV fMA.Criterion];
            phiFF=[fFF.pCommon fFF.muP fFF.sigP fFF.sigA fFF.sigV fFF.Criterion];

            seed=920000+it*1000+is;
            old=rng;rng(seed,'twister');
            xA=randn(nCond,nSim);xV=randn(nCond,nSim);rng(old);

            base=struct('taskName',modelTask,'sA',repmat(sA,1,nSim),'sV',repmat(sV,1,nSim), ...
                'xAPre',xA,'xVPre',xV);

            p=base;p.iModel=1;
            [pMA,pC1]=computeRespDistrib_AVTernus_v4(phiMA,p);

            p=base;p.iModel=4;
            [pFFsame,~]=computeRespDistrib_AVTernus_v4(phiMA,p);
            [pFFbest,~]=computeRespDistrib_AVTernus_v4(phiFF,p);

            dSame=pMA(:,2)-pFFsame(:,2);
            dBest=pMA(:,2)-pFFbest(:,2);

            w=nTrials/sum(nTrials);
            rowSub(end+1,:)={char(sid),char(task), ...
                sum(w.*abs(dSame)),max(abs(dSame)), ...
                sum(w.*abs(dBest)),max(abs(dBest)), ...
                sum(w.*pC1),min(pC1),max(pC1),mean(pC1)}; %#ok<AGROW>

            for c=1:nCond
                rowCell(end+1,:)={char(sid),char(task),uv(c,1),uv(c,2), ...
                    dSame(c),dBest(c),pC1(c),nTrials(c)}; %#ok<AGROW>
            end
        end
    end

    bySub=cell2table(rowSub,'VariableNames',{'Subject','Task', ...
        'MeanAbsDeltaP_SameParams','MaxAbsDeltaP_SameParams', ...
        'MeanAbsDeltaP_BestFits','MaxAbsDeltaP_BestFits', ...
        'WeightedMeanPC1_MA','MinPC1_MA','MaxPC1_MA','MeanPC1_MA'});

    byCell=cell2table(rowCell,'VariableNames',{'Subject','Task','ISI_A','ISI_V', ...
        'DeltaP_SameParams','DeltaP_BestFits','PC1_MA','NTrials'});
end

function fig=plotOverlapHeatmaps(cells)
    tasks=["AttendV","AttendA"];
    levels=[30 60 90 120 150 180 210];

    fig=figure('Color','w','Position',[80 80 1250 700]);
    tiledlayout(2,3,'Padding','compact','TileSpacing','compact');

    for it=1:numel(tasks)
        x=cells(string(cells.Task)==tasks(it),:);

        M1=nan(7);M2=nan(7);M3=nan(7);
        for ia=1:7
            for iv=1:7
                z=x(x.ISI_A==levels(ia)&x.ISI_V==levels(iv),:);
                M1(ia,iv)=mean(abs(z.DeltaP_SameParams),'omitnan');
                M2(ia,iv)=mean(abs(z.DeltaP_BestFits),'omitnan');
                M3(ia,iv)=mean(z.PC1_MA,'omitnan');
            end
        end

        nexttile((it-1)*3+1);
        imagesc(levels,levels,M1);axis xy;colorbar;
        xlabel('ISI_V (ms)');ylabel('ISI_A (ms)');
        title(sprintf('%s | mean |MA-FF| same params',tasks(it)));

        nexttile((it-1)*3+2);
        imagesc(levels,levels,M2);axis xy;colorbar;
        xlabel('ISI_V (ms)');ylabel('ISI_A (ms)');
        title(sprintf('%s | mean |MA-FF| best fits',tasks(it)));

        nexttile((it-1)*3+3);
        imagesc(levels,levels,M3,[0 1]);axis xy;colorbar;
        xlabel('ISI_V (ms)');ylabel('ISI_A (ms)');
        title(sprintf('%s | MA posterior P(C=1)',tasks(it)));
    end
end

function out=buildBoundaryDiagnostics(realFits,recoveryFits,tolFrac)
    LB=[0.001,-180,1,1,1,-180];
    UB=[0.999,180,250,250,250,180];
    names=["pCommon","muP","sigP","sigA","sigV","Criterion"];
    models=["ModelAveraging","ForcedFusion","Segregation"];
    tasks=["AttendV","AttendA"];
    rows=cell(0,9);

    for it=1:numel(tasks)
        for im=1:numel(models)
            x=realFits(string(realFits.Task)==tasks(it)&string(realFits.Model)==models(im)& ...
                string(realFits.Coordinate)=="pse_centered",:);
            for ip=1:numel(names)
                if models(im)~="ModelAveraging" && names(ip)=="pCommon",continue;end
                vals=x.(char(names(ip)));
                [n,nLow,nHigh]=nearBoundary(vals,LB(ip),UB(ip),tolFrac);
                rows(end+1,:)={'RealFit',char(tasks(it)),char(models(im)),char(names(ip)), ...
                    n,nLow,nHigh,nLow/max(n,1),nHigh/max(n,1)}; %#ok<AGROW>
            end

            xr=recoveryFits(string(recoveryFits.Task)==tasks(it)& ...
                string(recoveryFits.GeneratingModel)==models(im)& ...
                string(recoveryFits.FittedModel)==models(im),:);
            for ip=1:numel(names)
                if models(im)~="ModelAveraging" && names(ip)=="pCommon",continue;end
                vals=xr.(['Fit_' char(names(ip))]);
                [n,nLow,nHigh]=nearBoundary(vals,LB(ip),UB(ip),tolFrac);
                rows(end+1,:)={'SelfRecovery',char(tasks(it)),char(models(im)),char(names(ip)), ...
                    n,nLow,nHigh,nLow/max(n,1),nHigh/max(n,1)}; %#ok<AGROW>
            end
        end
    end

    out=cell2table(rows,'VariableNames',{'Source','Task','Model','Parameter','N', ...
        'NearLower','NearUpper','PropNearLower','PropNearUpper'});
end

function [n,nLow,nHigh]=nearBoundary(vals,lb,ub,tolFrac)
    vals=double(vals(:));vals=vals(isfinite(vals));n=numel(vals);
    tol=(ub-lb)*tolFrac;
    nLow=sum(vals<=lb+tol);
    nHigh=sum(vals>=ub-tol);
end

function out=validateBaselineVsModelReliability(rel,fits)
    tasks=["AttendV","AttendA"];
    models=["ModelAveraging","ForcedFusion"];
    rows=cell(0,9);

    for it=1:numel(tasks)
        for im=1:numel(models)
            x=fits(string(fits.Task)==tasks(it)&string(fits.Model)==models(im)& ...
                string(fits.Coordinate)=="pse_centered",:);
            if isempty(x),continue;end
            x.Subject=string(x.Subject);

            m=innerjoin(rel,x(:,{'Subject','sigA','sigV'}),'Keys','Subject');
            if height(m)<3,continue;end

            modPrecA=1./m.sigA.^2;
            modPrecV=1./m.sigV.^2;
            modRatio=log(modPrecA./modPrecV);

            [rA,pA]=corr(m.LogPrecision_A,log(modPrecA),'Rows','complete','Type','Pearson');
            [rV,pV]=corr(m.LogPrecision_V,log(modPrecV),'Rows','complete','Type','Pearson');
            [rR,pR]=corr(m.LogRelRatio_AoverV,modRatio,'Rows','complete','Type','Pearson');

            rows(end+1,:)={char(tasks(it)),char(models(im)),height(m), ...
                rA,pA,rV,pV,rR,pR}; %#ok<AGROW>
        end
    end

    out=cell2table(rows,'VariableNames',{'Task','Model','N', ...
        'r_BaselineA_vs_ModelA','p_BaselineA_vs_ModelA', ...
        'r_BaselineV_vs_ModelV','p_BaselineV_vs_ModelV', ...
        'r_BaselineRatio_vs_ModelRatio','p_BaselineRatio_vs_ModelRatio'});
end

function [comp,coef]=runCausalReliabilityModels(tbl,rel,ids)
    d=tbl(ismember(string(tbl.Subject),ids)&ismember(string(tbl.Task),["AttendV","AttendA"]),:);
    d=d(isfinite(d.RespCausal)&isfinite(d.AbsPSECenteredDiff)&isfinite(d.Direction),:);

    d.Subject=string(d.Subject);
    d.Task=string(d.Task);
    d=innerjoin(d,rel(:,{'Subject','JointJNDProxy','LogJointPrecisionC'}),'Keys','Subject');

    d.SubjectCat=categorical(d.Subject);
    d.TaskCat=categorical(d.Task,{'AttendV','AttendA'});
    d.DirectionCat=categorical(d.Direction);
    d.Dms30=d.AbsPSECenteredDiff/30;
    d.DJointJND=d.AbsPSECenteredDiff./d.JointJNDProxy;

    formulas={ ...
        'RespCausal ~ TaskCat + DirectionCat + Dms30 + TaskCat:Dms30 + (1|SubjectCat)', ...
        'RespCausal ~ TaskCat + DirectionCat + DJointJND + TaskCat:DJointJND + (1|SubjectCat)', ...
        'RespCausal ~ TaskCat + DirectionCat + Dms30 + LogJointPrecisionC + Dms30:LogJointPrecisionC + TaskCat:Dms30 + (1|SubjectCat)'};
    names=["PSECentered_ms","JointJND_Disparity","Disparity_x_JointPrecision"];

    rows=cell(0,7);coef=table();
    for i=1:numel(formulas)
        try
            m=fitglme(d,formulas{i},'Distribution','Binomial','Link','logit','FitMethod','Laplace');
            rows(end+1,:)={char(names(i)),height(d),numel(unique(d.Subject)), ...
                m.ModelCriterion.AIC,m.ModelCriterion.BIC,m.LogLikelihood,formulas{i}}; %#ok<AGROW>
            c=m.Coefficients;
            if isa(c,'dataset')
                c=dataset2table(c);
            end
            if ~istable(c)
                try
                    c=struct2table(c);
                catch
                    error('Could not convert model coefficients to a table.');
                end
            end
            c.Model=repmat(names(i),height(c),1);
            if isempty(coef)
                coef=c;
            else
                coef=[coef;c]; %#ok<AGROW>
            end
        catch ME
            warning('Causal reliability model %s failed: %s',names(i),ME.message);
        end
    end
    comp=cell2table(rows,'VariableNames',{'Model','NTrials','NSubjects','AIC','BIC','LogLikelihood','Formula'});
end

function [comp,coef]=runMotionReliabilityModels(tbl,rel,ids)
    d=tbl(ismember(string(tbl.Subject),ids)&ismember(string(tbl.Task),["AttendV","AttendA"]),:);
    d=d(isfinite(d.RespMotion)&isfinite(d.TargetCentered)&isfinite(d.DistractorCentered)&isfinite(d.Direction),:);

    d.Subject=string(d.Subject);
    d.Task=string(d.Task);
    d=innerjoin(d,rel(:,{'Subject','Precision_A','Precision_V'}),'Keys','Subject');

    d.SubjectCat=categorical(d.Subject);
    d.TaskCat=categorical(d.Task,{'AttendV','AttendA'});
    d.DirectionCat=categorical(d.Direction);
    d.Target30C=d.TargetCentered/30;
    d.Distractor30C=d.DistractorCentered/30;

    relBalance=nan(height(d),1);
    iv=d.Task=="AttendV";
    ia=d.Task=="AttendA";
    relBalance(iv)=log(d.Precision_A(iv)./d.Precision_V(iv)); % distractor A / target V
    relBalance(ia)=log(d.Precision_V(ia)./d.Precision_A(ia)); % distractor V / target A
    d.RelBalance=relBalance;
    d.RelBalanceC=d.RelBalance-mean(d.RelBalance,'omitnan');

    formulas={ ...
        'RespMotion ~ TaskCat + DirectionCat + Target30C + Distractor30C + TaskCat:Target30C + TaskCat:Distractor30C + (1|SubjectCat)', ...
        'RespMotion ~ TaskCat + DirectionCat + Target30C + Distractor30C + TaskCat:Target30C + TaskCat:Distractor30C + RelBalanceC + Target30C:RelBalanceC + Distractor30C:RelBalanceC + (1|SubjectCat)'};
    names=["Base_TargetDistractor","Plus_RelativeReliability"];

    rows=cell(0,7);coef=table();
    for i=1:numel(formulas)
        try
            m=fitglme(d,formulas{i},'Distribution','Binomial','Link','logit','FitMethod','Laplace');
            rows(end+1,:)={char(names(i)),height(d),numel(unique(d.Subject)), ...
                m.ModelCriterion.AIC,m.ModelCriterion.BIC,m.LogLikelihood,formulas{i}}; %#ok<AGROW>
            c=m.Coefficients;
            if isa(c,'dataset')
                c=dataset2table(c);
            end
            if ~istable(c)
                try
                    c=struct2table(c);
                catch
                    error('Could not convert model coefficients to a table.');
                end
            end
            c.Model=repmat(names(i),height(c),1);
            if isempty(coef)
                coef=c;
            else
                coef=[coef;c]; %#ok<AGROW>
            end
        catch ME
            warning('Motion reliability model %s failed: %s',names(i),ME.message);
        end
    end
    comp=cell2table(rows,'VariableNames',{'Model','NTrials','NSubjects','AIC','BIC','LogLikelihood','Formula'});
end

function out=buildReliabilitySummary(validation,cComp,cCoef,mComp,mCoef)
    rows=cell(0,4);

    for i=1:height(validation)
        rows(end+1,:)={'Validation', ...
            sprintf('%s / %s A precision correlation',validation.Task{i},validation.Model{i}), ...
            validation.r_BaselineA_vs_ModelA(i),validation.p_BaselineA_vs_ModelA(i)}; %#ok<AGROW>
        rows(end+1,:)={'Validation', ...
            sprintf('%s / %s V precision correlation',validation.Task{i},validation.Model{i}), ...
            validation.r_BaselineV_vs_ModelV(i),validation.p_BaselineV_vs_ModelV(i)}; %#ok<AGROW>
        rows(end+1,:)={'Validation', ...
            sprintf('%s / %s A/V ratio correlation',validation.Task{i},validation.Model{i}), ...
            validation.r_BaselineRatio_vs_ModelRatio(i),validation.p_BaselineRatio_vs_ModelRatio(i)}; %#ok<AGROW>
    end

    if ~isempty(cComp)
        for i=1:height(cComp)
            rows(end+1,:)={'CausalModelBIC',char(string(cComp.Model(i))),cComp.BIC(i),NaN}; %#ok<AGROW>
        end
    end

    if ~isempty(cCoef) && ismember('Name',cCoef.Properties.VariableNames)
        idx=contains(string(cCoef.Name),'Dms30:LogJointPrecisionC');
        for i=find(idx)'
            rows(end+1,:)={'CausalInteraction',char(string(cCoef.Model(i))),cCoef.Estimate(i),cCoef.pValue(i)}; %#ok<AGROW>
        end
    end

    if ~isempty(mComp)
        for i=1:height(mComp)
            rows(end+1,:)={'MotionModelBIC',char(string(mComp.Model(i))),mComp.BIC(i),NaN}; %#ok<AGROW>
        end
    end

    if ~isempty(mCoef) && ismember('Name',mCoef.Properties.VariableNames)
        idx=contains(string(mCoef.Name),'Distractor30C:RelBalanceC');
        for i=find(idx)'
            rows(end+1,:)={'MotionDistractorReliabilityInteraction',char(string(mCoef.Model(i))), ...
                mCoef.Estimate(i),mCoef.pValue(i)}; %#ok<AGROW>
        end
    end

    out=cell2table(rows,'VariableNames',{'Section','Metric','Value','p'});
end

function [entries,summary]=auditSettingMetadata(fileAudit)
    selected=fileAudit(fileAudit.Selected,:);
    pattern='(?i)(wfi|ifi|refresh|frame|hz|reliab|bright|lumin|audio|volume|gain|amp|device|screen|setting|stimulus|beep|tone)';
    rows=cell(0,5);

    for i=1:height(selected)
        fp=char(selected.FullPath(i));
        sid=char(string(selected.Subject(i)));
        fn=char(string(selected.FileName(i)));

        % Nested P metadata.
        try
            x=load(fp,'P');
            if isfield(x,'P')
                pairs=flattenMetadata(x.P,'P',0,4);
                for j=1:size(pairs,1)
                    fpath=pairs{j,1};
                    val=pairs{j,2};
                    if ~isempty(regexp(fpath,pattern,'once'))
                        rows(end+1,:)={sid,fn,'P',fpath,val}; %#ok<AGROW>
                    end
                end
            end
        catch ME
            warning('Metadata P audit failed for %s: %s',fn,ME.message);
        end

        % Top-level candidate variables (small values only).
        try
            info=whos('-file',fp);
            for j=1:numel(info)
                nm=info(j).name;
                if strcmp(nm,'P')||strcmp(nm,'T'),continue;end
                if isempty(regexp(nm,pattern,'once')),continue;end
                if prod(info(j).size)>100,continue;end
                try
                    z=load(fp,nm);
                    val=valueToString(z.(nm));
                    rows(end+1,:)={sid,fn,'TopLevel',nm,val}; %#ok<AGROW>
                catch
                end
            end
        catch
        end
    end

    entries=cell2table(rows,'VariableNames',{'Subject','FileName','Source','FieldPath','Value'});

    if isempty(entries)
        summary=table();
        return;
    end

    fields=unique(string(entries.FieldPath),'stable');
    srows=cell(0,5);
    for i=1:numel(fields)
        x=entries(string(entries.FieldPath)==fields(i),:);
        vals=unique(string(x.Value));
        ex=strjoin(cellstr(vals(1:min(6,numel(vals)))),', ');
        srows(end+1,:)={char(fields(i)),height(x),numel(unique(string(x.Subject))),numel(vals),ex}; %#ok<AGROW>
    end
    summary=cell2table(srows,'VariableNames',{'FieldPath','NEntries','NSubjects','NUniqueValues','ExampleValues'});
end

function pairs=flattenMetadata(x,prefix,depth,maxDepth)
    pairs=cell(0,2);
    if depth>maxDepth,return;end
    if isstruct(x) && isscalar(x)
        f=fieldnames(x);
        for i=1:numel(f)
            v=x.(f{i});
            p=[prefix '.' f{i}];
            if isstruct(v) && isscalar(v)
                sub=flattenMetadata(v,p,depth+1,maxDepth);
                pairs=[pairs;sub]; %#ok<AGROW>
            elseif isSimpleMetadataValue(v)
                pairs(end+1,:)={p,valueToString(v)}; %#ok<AGROW>
            end
        end
    end
end

function tf=isSimpleMetadataValue(v)
    tf=false;
    if isnumeric(v)||islogical(v)
        tf=numel(v)<=20;
    elseif ischar(v)
        tf=numel(v)<=200;
    elseif isstring(v)||iscategorical(v)
        tf=numel(v)<=20;
    elseif iscell(v) && numel(v)<=10
        tf=true;
        for i=1:numel(v)
            if ~(ischar(v{i})||isstring(v{i})||(isnumeric(v{i})&&isscalar(v{i}))||islogical(v{i}))
                tf=false;break;
            end
        end
    end
end

function s=valueToString(v)
    try
        if isnumeric(v)||islogical(v)
            if isempty(v),s='';else,s=strtrim(sprintf('%.8g ',double(v(:))));end
        elseif ischar(v)
            s=strtrim(v);
        elseif isstring(v)||iscategorical(v)
            s=strjoin(cellstr(string(v(:))),' | ');
        elseif iscell(v)
            z=strings(numel(v),1);
            for i=1:numel(v)
                if isnumeric(v{i})||islogical(v{i})
                    z(i)=string(v{i});
                else
                    z(i)=string(v{i});
                end
            end
            s=strjoin(cellstr(z),' | ');
        else
            s=class(v);
        end
    catch
        s='<unreadable>';
    end
end

function saveFigure(fig,path)
    try
        exportgraphics(fig,path,'Resolution',250);
    catch
        saveas(fig,path);
    end
end
