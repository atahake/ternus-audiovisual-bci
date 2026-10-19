%% run_BCI_model_comparison_v4.m
% Audiovisual Ternus study - v4 main analysis entry point
%
% This script is written for the real experiment paths and real *.mat table
% structure produced by runExperimentBlock.m.
%
% FIRST RUN RECOMMENDATION:
%   Keep RUN_BCI_MODELS = false.
%   The script will complete raw-data audit, baseline psychometrics/QC,
%   trial-level behavioral analyses, 7x7 summaries, coordinate comparisons,
%   and a code-level timing audit. No experimental condition is removed.
%   Paste Key_Results_To_Paste_v4.txt back to ChatGPT before enabling the
%   computational-model section.
%
% Required scripts in SCRIPT_DIR:
%   run_BCI_model_comparison_v4.m
%   audit_AV_timing.m
%   computeNegLL_AVTernus_v4.m
%   computeRespDistrib_AVTernus_v4.m
%
% Required MATLAB toolbox for Phase 1:
%   Statistics and Machine Learning Toolbox (glmfit, fitglme, ttest)
%
% Optional for later BCI group model selection:
%   SPM12 (spm_BMS). If absent, group BIC weights are still computed.

clear; clc; close all;
rng(20260908,'twister');

%% ============================ PATHS ====================================
DATA_DIR = 'C:\MSI\oscillation\ternus AV BCI\Data0714\Data';
ANALYSIS_ROOT = 'C:\MSI\oscillation\ternus AV BCI\analysis0906';
SCRIPT_DIR = fullfile(ANALYSIS_ROOT,'analysis');
OUT_DIR = fullfile(ANALYSIS_ROOT,'Analysis_Output_v4');

if ~exist(DATA_DIR,'dir'), error('DATA_DIR does not exist: %s',DATA_DIR); end
if ~exist(ANALYSIS_ROOT,'dir'), error('ANALYSIS_ROOT does not exist: %s',ANALYSIS_ROOT); end
if ~exist(SCRIPT_DIR,'dir'), error('SCRIPT_DIR does not exist: %s',SCRIPT_DIR); end
if ~exist(OUT_DIR,'dir'), mkdir(OUT_DIR); end
addpath(SCRIPT_DIR);

assert(exist('audit_AV_timing','file')==2,'Missing audit_AV_timing.m in %s',SCRIPT_DIR);
assert(exist('computeNegLL_AVTernus_v4','file')==2,'Missing computeNegLL_AVTernus_v4.m in %s',SCRIPT_DIR);
assert(exist('computeRespDistrib_AVTernus_v4','file')==2,'Missing computeRespDistrib_AVTernus_v4.m in %s',SCRIPT_DIR);
assert(exist('fitglme','file')==2,'fitglme is unavailable. Statistics and Machine Learning Toolbox is required.');

%% ========================= USER SETTINGS ===============================
% Phase 1 should be run first. After inspecting the results with ChatGPT,
% this can be switched to true without changing any file paths.
RUN_BCI_MODELS = false;

% Keep the legacy v3 QC thresholds for continuity, but report every reason.
LAPSE_CUTOFF = 0.20;
PSE_ABS_MAX = 450;
LOW_SLACK_THRESHOLD_MS = 10;

% Complete-file duplicate policy. If the same participant has multiple
% Complete files for one BlockType, the latest P.startTime is used and all
% alternatives remain listed in File_Audit.csv.
DUPLICATE_BLOCK_POLICY = 'latest';

% Later BCI settings (ignored while RUN_BCI_MODELS=false).
N_SIM = 3000;
N_STARTS = 8;
COORD_MODES = {'raw','pse_centered','perceptual'};
TIMING_SCOPES = {'full'};
MODEL_CODES = [1 4 5];
MODEL_NAMES = {'ModelAveraging','ForcedFusion','Segregation'};
MODEL_K = [6 5 5];

%% ============================== LOG ====================================
reportFile = fullfile(OUT_DIR,'Analysis_Report_v4.txt');
if exist(reportFile,'file'), delete(reportFile); end
diary(reportFile); diary on;
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('=====================================================================\n');
fprintf(' Audiovisual Ternus v4 analysis\n');
fprintf(' Data:    %s\n',DATA_DIR);
fprintf(' Scripts: %s\n',SCRIPT_DIR);
fprintf(' Output:  %s\n',OUT_DIR);
fprintf(' Started: %s\n',datestr(now));
fprintf(' RUN_BCI_MODELS = %d\n',RUN_BCI_MODELS);
fprintf('=====================================================================\n\n');

%% ================== 1. DISCOVER AND SELECT FILES =======================
fprintf('[1/8] Discovering Complete.mat files and resolving duplicates...\n');
fileAudit = discoverCompleteFiles(DATA_DIR,DUPLICATE_BLOCK_POLICY);
writetable(fileAudit,fullfile(OUT_DIR,'File_Audit.csv'));
selectedFiles = fileAudit(fileAudit.Selected,:);

fprintf('Complete files found: %d\n',height(fileAudit));
fprintf('Files selected for analysis: %d\n',height(selectedFiles));
fprintf('Unique participants: %d\n\n',numel(unique(string(selectedFiles.Subject))));

%% ====================== 2. LOAD REAL TRIAL TABLES ======================
fprintf('[2/8] Loading selected T tables and validating response-key mappings...\n');
trialTable = buildRealTrialTable(selectedFiles);
subjectAudit = buildSubjectAudit(trialTable,fileAudit);
writetable(subjectAudit,fullfile(OUT_DIR,'Subject_Design_Audit.csv'));
writetable(trialTable,fullfile(OUT_DIR,'Trial_Level_Data_v4.csv'));

fprintf('Loaded trials: %d\n',height(trialTable));
fprintf('Participants with complete programmed design: %d / %d\n\n', ...
    sum(subjectAudit.CompleteDesign),height(subjectAudit));

%% ================= 3. BASELINE PSYCHOMETRICS + QC ======================
fprintf('[3/8] Fitting visual and auditory baseline psychometrics...\n');
qualityTable = buildQualityTable(trialTable,subjectAudit,LAPSE_CUTOFF,PSE_ABS_MAX);
writetable(qualityTable,fullfile(OUT_DIR,'Subject_QC_v4.csv'));

includedIDs = string(qualityTable.ID(qualityTable.Included));
excludedIDs = string(qualityTable.ID(~qualityTable.Included));
fprintf('Participants passing v4 primary QC: %d / %d\n',numel(includedIDs),height(qualityTable));
if ~isempty(excludedIDs)
    fprintf('Excluded/flagged participants: %s\n',strjoin(cellstr(excludedIDs),', '));
end
fprintf('\n');

baseStats = baselineStatistics(qualityTable(qualityTable.Included,:));
writetable(baseStats,fullfile(OUT_DIR,'Baseline_Statistics_v4.csv'));
fig1 = plotBaselineFigure(qualityTable(qualityTable.Included,:));
saveFigure(fig1,fullfile(OUT_DIR,'Figure_01_Baseline_v4.png'));

%% ================= 4. ADD PERCEPTUAL COORDINATES =======================
fprintf('[4/8] Adding subject-specific perceptual coordinates and code-level timing-audit metadata...\n');
timingAudit = audit_AV_timing(30:30:210,LOW_SLACK_THRESHOLD_MS, ...
    fullfile(OUT_DIR,'Timing_Code_Audit.csv'));
trialTable = addDerivedTrialVariables(trialTable,qualityTable,LOW_SLACK_THRESHOLD_MS);
writetable(trialTable,fullfile(OUT_DIR,'Trial_Level_Data_v4.csv')); % overwrite with derived columns

avMask = ismember(string(trialTable.Task),["AttendV","AttendA"]);
fprintf('AV trials in all selected files: %d\n',sum(avMask));
fprintf('Trials flagged by the code-level timing audit: %d (%.2f%%). These trials are retained in all analyses.\n\n', ...
    sum(avMask & trialTable.CodeTimingRisk), ...
    100*sum(avMask & trialTable.CodeTimingRisk)/max(1,sum(avMask)));

%% ======================= 5. 7x7 BEHAVIOR ================================
fprintf('[5/8] Building subject-balanced 7x7 empirical response surfaces...\n');
analysisTrials = trialTable(ismember(string(trialTable.Subject),includedIDs),:);
heatmapTable = buildHeatmapTable(analysisTrials);
writetable(heatmapTable,fullfile(OUT_DIR,'AV_7x7_Group_Response_Surfaces.csv'));
fig2 = plotAVHeatmaps(heatmapTable);
saveFigure(fig2,fullfile(OUT_DIR,'Figure_02_AV_7x7_Heatmaps_v4.png'));

%% ================= 6. TRIAL-LEVEL BEHAVIORAL GLMES =====================
fprintf('[6/8] Running motion and explicit-causality GLMEs...\n');
[behaviorCoef,causalCoordinateComparison,modelObjects] = runBehaviorGLMEs(analysisTrials);
writetable(behaviorCoef,fullfile(OUT_DIR,'Behavior_GLME_Coefficients_v4.csv'));
writetable(causalCoordinateComparison,fullfile(OUT_DIR,'Causal_Coordinate_Comparison_v4.csv'));
save(fullfile(OUT_DIR,'Behavior_GLME_Models_v4.mat'),'modelObjects','-v7.3');

fprintf('\nCausal-coordinate comparison:\n');
disp(causalCoordinateComparison);

%% ================= 6B. COORDINATE / SAMPLE ROBUSTNESS =================
fprintf('[6b/8] Running full-grid coordinate, sample-QC, and direction robustness analyses...\n');
completeDesignIDs = string(subjectAudit.ID(subjectAudit.CompleteDesign));
[phase1bCoef,phase1bCoordComp,phase1bMotionComp,baselineDirectionCoef,phase1bObjects] = ...
    runPhase1bAnalyses(trialTable,qualityTable,includedIDs,completeDesignIDs);

writetable(phase1bCoef,fullfile(OUT_DIR,'Phase1b_GLME_Coefficients_v4.csv'));
writetable(phase1bCoordComp,fullfile(OUT_DIR,'Phase1b_Causal_Coordinate_Comparison_v4.csv'));
writetable(phase1bMotionComp,fullfile(OUT_DIR,'Phase1b_Motion_Coordinate_Comparison_v4.csv'));
writetable(baselineDirectionCoef,fullfile(OUT_DIR,'Phase1b_Baseline_Direction_Check_v4.csv'));
save(fullfile(OUT_DIR,'Phase1b_GLME_Models_v4.mat'),'phase1bObjects','-v7.3');

fprintf('\nPhase-1b causal coordinate comparison:\n');
disp(phase1bCoordComp);
fprintf('\nPhase-1b motion coordinate comparison:\n');
disp(phase1bMotionComp);

%% ================= 7. OPTIONAL FIRST-PASS BCI MODELS ===================
if RUN_BCI_MODELS
    fprintf('[7/8] RUN_BCI_MODELS=true: fitting first-pass BCI models...\n');
    [bciFits,bciEvidence] = fitBCIModels(analysisTrials,qualityTable, ...
        N_SIM,N_STARTS,COORD_MODES,TIMING_SCOPES,MODEL_CODES,MODEL_NAMES,MODEL_K);
    writetable(bciFits,fullfile(OUT_DIR,'BCI_v4_Subject_Model_Fits.csv'));
    writetable(bciEvidence,fullfile(OUT_DIR,'BCI_v4_Group_Model_Evidence.csv'));
    save(fullfile(OUT_DIR,'BCI_v4_Results.mat'),'bciFits','bciEvidence', ...
        'COORD_MODES','TIMING_SCOPES','MODEL_CODES','MODEL_NAMES','-v7.3');
else
    fprintf('[7/8] BCI model fitting skipped intentionally on the first run.\n');
    fprintf('      Review Phase-1 results first, then set RUN_BCI_MODELS=true.\n\n');
    bciFits = table(); %#ok<NASGU>
    bciEvidence = table(); %#ok<NASGU>
end

%% ===================== 8. SAVE + PASTE SUMMARY =========================
fprintf('[8/8] Saving combined results and concise paste-back summary...\n');
save(fullfile(OUT_DIR,'Phase1_Analysis_Results_v4.mat'), ...
    'fileAudit','subjectAudit','qualityTable','baseStats','trialTable', ...
    'timingAudit','heatmapTable','behaviorCoef','causalCoordinateComparison', ...
    'phase1bCoef','phase1bCoordComp','phase1bMotionComp','baselineDirectionCoef','-v7.3');

summaryFile = fullfile(OUT_DIR,'Key_Results_To_Paste_v4.txt');
writeKeySummary(summaryFile,fileAudit,subjectAudit,qualityTable,baseStats, ...
    timingAudit,behaviorCoef,causalCoordinateComparison,RUN_BCI_MODELS,bciEvidence);
appendPhase1bSummary(summaryFile,phase1bCoordComp,phase1bMotionComp, ...
    phase1bCoef,baselineDirectionCoef);

fprintf('\n=====================================================================\n');
fprintf('Phase-1 analysis finished.\n');
fprintf('Please paste this file back to ChatGPT:\n  %s\n',summaryFile);
fprintf('Full report:\n  %s\n',reportFile);
fprintf('Finished: %s\n',datestr(now));
fprintf('=====================================================================\n');
diary off;

%% ======================================================================
% LOCAL FUNCTIONS
% =======================================================================

function fileAudit = discoverCompleteFiles(dataDir,duplicatePolicy)
    files = dir(fullfile(dataDir,'*_Complete.mat'));
    if isempty(files)
        error('No *_Complete.mat files found in %s',dataDir);
    end

    n = numel(files);
    FileName = strings(n,1); FullPath = strings(n,1); Subject = strings(n,1);
    BlockType = nan(n,1); StartTime = NaT(n,1); StartText = strings(n,1);
    FileDateNum = nan(n,1);

    for i=1:n
        FileName(i) = string(files(i).name);
        FullPath(i) = string(fullfile(files(i).folder,files(i).name));
        FileDateNum(i) = files(i).datenum;
        try
            S = load(char(FullPath(i)),'P');
            if isfield(S,'P')
                if isfield(S.P,'subID'), Subject(i)=string(S.P.subID); end
                if isfield(S.P,'blockType'), BlockType(i)=double(S.P.blockType); end
                if isfield(S.P,'startTime')
                    StartText(i)=string(S.P.startTime);
                    try
                        StartTime(i)=datetime(StartText(i),'InputFormat','yyyy-MM-dd HH:mm:ss');
                    catch
                        try, StartTime(i)=datetime(StartText(i)); catch, end
                    end
                end
            end
        catch ME
            warning('Could not read P from %s: %s',files(i).name,ME.message);
        end

        if strlength(Subject(i))==0 || ~isfinite(BlockType(i))
            tok = regexp(files(i).name,'^(.*?)_Block([0-2])_','tokens','once');
            if ~isempty(tok)
                if strlength(Subject(i))==0, Subject(i)=string(tok{1}); end
                if ~isfinite(BlockType(i)), BlockType(i)=str2double(tok{2}); end
            end
        end
    end

    validMeta = strlength(Subject)>0 & isfinite(BlockType);
    if any(~validMeta)
        warning('%d Complete files have unresolved subject/block metadata and will not be selected.',sum(~validMeta));
    end

    SelectionTime = FileDateNum;
    okDT = ~isnat(StartTime);
    if any(okDT)
        SelectionTime(okDT) = datenum(StartTime(okDT));
    end

    Selected = false(n,1);
    DuplicateBlock = false(n,1);
    DuplicateCount = zeros(n,1);

    validIdx = find(validMeta);
    keys = Subject(validIdx) + "|" + string(BlockType(validIdx));
    uKeys = unique(keys,'stable');
    for k=1:numel(uKeys)
        idxLocal = validIdx(keys==uKeys(k));
        DuplicateCount(idxLocal)=numel(idxLocal);
        DuplicateBlock(idxLocal)=numel(idxLocal)>1;
        switch lower(duplicatePolicy)
            case 'latest'
                [~,j]=max(SelectionTime(idxLocal));
                Selected(idxLocal(j))=true;
            case 'error'
                if numel(idxLocal)>1
                    error('Duplicate Complete files for %s. Resolve manually.',uKeys(k));
                end
                Selected(idxLocal)=true;
            otherwise
                error('Unknown DUPLICATE_BLOCK_POLICY: %s',duplicatePolicy);
        end
    end

    fileAudit = table(FileName,FullPath,Subject,BlockType,StartText,StartTime, ...
        DuplicateBlock,DuplicateCount,Selected);
    fileAudit = sortrows(fileAudit,{'Subject','BlockType','StartTime'});
end

function trialTable = buildRealTrialTable(selectedFiles)
    trialTable = table();

    for i=1:height(selectedFiles)
        filePath = char(selectedFiles.FullPath(i));
        S = load(filePath,'T','P');
        if ~isfield(S,'T') || ~istable(S.T)
            error('File does not contain MATLAB table T: %s',filePath);
        end
        if ~isfield(S,'P')
            error('File does not contain struct P: %s',filePath);
        end
        T = S.T; P = S.P;

        required = {'Task','ISI_V','ISI_A','Direction','Resp_Motion','Phys_Motion', ...
                    'RT_Motion','Resp_Causal','Phys_Causal','RT_Causal'};
        missing = setdiff(required,T.Properties.VariableNames);
        if ~isempty(missing)
            error('Missing columns in %s: %s',filePath,strjoin(missing,', '));
        end

        n = height(T);
        Subject = repmat(string(P.subID),n,1);
        BlockType = repmat(double(P.blockType),n,1);
        FileName = repmat(string(selectedFiles.FileName(i)),n,1);
        TrialInFile = (1:n)';

        rawTask = normalizeTextColumn(T.Task);
        Task = strings(n,1); TaskID=zeros(n,1);
        Task(rawTask=="baseline_v")="BaselineV"; TaskID(rawTask=="baseline_v")=1;
        Task(rawTask=="baseline_a")="BaselineA"; TaskID(rawTask=="baseline_a")=2;
        Task(rawTask=="attend_v")="AttendV";   TaskID(rawTask=="attend_v")=3;
        Task(rawTask=="attend_a")="AttendA";   TaskID(rawTask=="attend_a")=4;
        if any(TaskID==0)
            bad=unique(rawTask(TaskID==0));
            error('Unknown Task labels in %s: %s',filePath,strjoin(cellstr(bad),', '));
        end

        ISI_V = toDoubleColumn(T.ISI_V);
        ISI_A = toDoubleColumn(T.ISI_A);
        Direction = toDoubleColumn(T.Direction);
        RespMotion = decodeBinaryStrict(T.Resp_Motion,["group","group motion","1"],["elem","element","element motion","0"]);
        RespCausal = decodeBinaryStrict(T.Resp_Causal,["common","common source","unity","same","1"],["separate","separate source","different","0","2"]);
        PhysMotion = normalizeTextColumn(T.Phys_Motion);
        PhysCausal = normalizeTextColumn(T.Phys_Causal);
        RTMotion = toDoubleColumn(T.RT_Motion);
        RTCausal = toDoubleColumn(T.RT_Causal);

        elemKey = getMapKey(P,'elem'); groupKey=getMapKey(P,'group');
        commonKey=getMapKey(P,'common'); separateKey=getMapKey(P,'separate');
        ExpectedMotionKey = strings(n,1);
        ExpectedMotionKey(RespMotion==0)=elemKey;
        ExpectedMotionKey(RespMotion==1)=groupKey;
        ExpectedCausalKey = strings(n,1);
        ExpectedCausalKey(RespCausal==1)=commonKey;
        ExpectedCausalKey(RespCausal==0)=separateKey;

        KeyMismatchMotion = isfinite(RespMotion) & strlength(PhysMotion)>0 & ...
                            PhysMotion~=ExpectedMotionKey;
        KeyMismatchCausal = isfinite(RespCausal) & strlength(PhysCausal)>0 & ...
                            PhysCausal~=ExpectedCausalKey;

        temp = table(Subject,BlockType,FileName,TrialInFile,Task,TaskID, ...
            ISI_V,ISI_A,Direction,RespMotion,PhysMotion,RTMotion, ...
            RespCausal,PhysCausal,RTCausal,ExpectedMotionKey,ExpectedCausalKey, ...
            KeyMismatchMotion,KeyMismatchCausal);
        trialTable = [trialTable; temp]; %#ok<AGROW>
    end
end

function subjectAudit = buildSubjectAudit(tbl,fileAudit)
    ids = unique(string(tbl.Subject),'stable');
    n=numel(ids);
    ID=strings(n,1); N_BaselineV=zeros(n,1); N_BaselineA=zeros(n,1);
    N_AttendV=zeros(n,1); N_AttendA=zeros(n,1);
    Cells_AttendV=zeros(n,1); Cells_AttendA=zeros(n,1);
    MinRep_AttendV=nan(n,1); MaxRep_AttendV=nan(n,1);
    MinRep_AttendA=nan(n,1); MaxRep_AttendA=nan(n,1);
    MotionMissing=zeros(n,1); CausalMissingAV=zeros(n,1);
    MotionKeyMismatch=zeros(n,1); CausalKeyMismatch=zeros(n,1);
    AttentionOrder=strings(n,1); ExpectedAttentionOrder=strings(n,1);
    OrderMatchesExpected=false(n,1); DuplicateBlocks=zeros(n,1);
    CompleteDesign=false(n,1);

    for s=1:n
        sid=ids(s); ID(s)=sid;
        d=tbl(string(tbl.Subject)==sid,:);
        N_BaselineV(s)=sum(string(d.Task)=="BaselineV");
        N_BaselineA(s)=sum(string(d.Task)=="BaselineA");
        N_AttendV(s)=sum(string(d.Task)=="AttendV");
        N_AttendA(s)=sum(string(d.Task)=="AttendA");
        [Cells_AttendV(s),MinRep_AttendV(s),MaxRep_AttendV(s)] = cellRepInfo(d,string(d.Task)=="AttendV");
        [Cells_AttendA(s),MinRep_AttendA(s),MaxRep_AttendA(s)] = cellRepInfo(d,string(d.Task)=="AttendA");
        MotionMissing(s)=sum(~isfinite(d.RespMotion));
        av=ismember(string(d.Task),["AttendV","AttendA"]);
        CausalMissingAV(s)=sum(av & ~isfinite(d.RespCausal));
        MotionKeyMismatch(s)=sum(d.KeyMismatchMotion);
        CausalKeyMismatch(s)=sum(d.KeyMismatchCausal);

        f=fileAudit(string(fileAudit.Subject)==sid & fileAudit.Selected,:);
        fV=f(f.BlockType==1,:); fA=f(f.BlockType==2,:);
        if ~isempty(fV) && ~isempty(fA) && ~isnat(fV.StartTime(1)) && ~isnat(fA.StartTime(1))
            if fV.StartTime(1)<fA.StartTime(1), AttentionOrder(s)="AttendV->AttendA";
            else, AttentionOrder(s)="AttendA->AttendV"; end
        else
            AttentionOrder(s)="Unknown";
        end
        numTok=regexp(char(sid),'\d+','match','once'); subNum=str2double(numTok);
        if isfinite(subNum)
            if mod(subNum,2)==1, ExpectedAttentionOrder(s)="AttendV->AttendA";
            else, ExpectedAttentionOrder(s)="AttendA->AttendV"; end
            OrderMatchesExpected(s)=AttentionOrder(s)==ExpectedAttentionOrder(s);
        else
            ExpectedAttentionOrder(s)="Unknown";
        end
        DuplicateBlocks(s)=sum(fileAudit.Subject==sid & fileAudit.DuplicateBlock & fileAudit.Selected);

        CompleteDesign(s) = N_BaselineV(s)==140 && N_BaselineA(s)==140 && ...
            N_AttendV(s)==490 && N_AttendA(s)==490 && ...
            Cells_AttendV(s)==49 && Cells_AttendA(s)==49 && ...
            MinRep_AttendV(s)==10 && MaxRep_AttendV(s)==10 && ...
            MinRep_AttendA(s)==10 && MaxRep_AttendA(s)==10 && ...
            MotionMissing(s)==0 && CausalMissingAV(s)==0 && ...
            MotionKeyMismatch(s)==0 && CausalKeyMismatch(s)==0;
    end

    subjectAudit=table(ID,N_BaselineV,N_BaselineA,N_AttendV,N_AttendA, ...
        Cells_AttendV,MinRep_AttendV,MaxRep_AttendV,Cells_AttendA,MinRep_AttendA,MaxRep_AttendA, ...
        MotionMissing,CausalMissingAV,MotionKeyMismatch,CausalKeyMismatch, ...
        AttentionOrder,ExpectedAttentionOrder,OrderMatchesExpected,DuplicateBlocks,CompleteDesign);
end

function [nCells,minRep,maxRep]=cellRepInfo(d,mask)
    x=d(mask,:);
    if isempty(x), nCells=0; minRep=NaN; maxRep=NaN; return; end
    valid=isfinite(x.ISI_A)&isfinite(x.ISI_V);
    x=x(valid,:);
    if isempty(x), nCells=0; minRep=NaN; maxRep=NaN; return; end
    [~,~,g]=unique([x.ISI_A,x.ISI_V],'rows');
    reps=accumarray(g,1);
    nCells=numel(reps); minRep=min(reps); maxRep=max(reps);
end

function q=buildQualityTable(tbl,audit,lapseCutoff,pseAbsMax)
    ids=string(audit.ID); n=numel(ids);
    V_PSE=nan(n,1); V_JND=nan(n,1); V_Lapse=nan(n,1); V_Slope=nan(n,1);
    A_PSE=nan(n,1); A_JND=nan(n,1); A_Lapse=nan(n,1); A_Slope=nan(n,1);
    Included=false(n,1); ExclusionReason=strings(n,1);

    for s=1:n
        d=tbl(string(tbl.Subject)==ids(s),:);
        v=d(string(d.Task)=="BaselineV" & isfinite(d.RespMotion) & isfinite(d.ISI_V),:);
        a=d(string(d.Task)=="BaselineA" & isfinite(d.RespMotion) & isfinite(d.ISI_A),:);
        [V_PSE(s),V_Lapse(s),V_JND(s),V_Slope(s)]=fitPsychometricUnified(v.ISI_V,v.RespMotion);
        [A_PSE(s),A_Lapse(s),A_JND(s),A_Slope(s)]=fitPsychometricUnified(a.ISI_A,a.RespMotion);

        reasons=strings(0,1);
        if ~audit.CompleteDesign(s), reasons(end+1)="incomplete or inconsistent programmed design"; end %#ok<AGROW>
        if ~all(isfinite([V_PSE(s),V_JND(s),V_Lapse(s),V_Slope(s)])), reasons(end+1)="invalid visual baseline fit"; end %#ok<AGROW>
        if ~all(isfinite([A_PSE(s),A_JND(s),A_Lapse(s),A_Slope(s)])), reasons(end+1)="invalid auditory baseline fit"; end %#ok<AGROW>
        if isfinite(V_Lapse(s)) && V_Lapse(s)>lapseCutoff, reasons(end+1)="visual edge-error rate > cutoff"; end %#ok<AGROW>
        if isfinite(A_Lapse(s)) && A_Lapse(s)>lapseCutoff, reasons(end+1)="auditory edge-error rate > cutoff"; end %#ok<AGROW>
        if isfinite(V_PSE(s)) && abs(V_PSE(s))>pseAbsMax, reasons(end+1)="visual PSE out of range"; end %#ok<AGROW>
        if isfinite(A_PSE(s)) && abs(A_PSE(s))>pseAbsMax, reasons(end+1)="auditory PSE out of range"; end %#ok<AGROW>
        if isfinite(V_JND(s)) && V_JND(s)<=0, reasons(end+1)="visual JND <= 0"; end %#ok<AGROW>
        if isfinite(A_JND(s)) && A_JND(s)<=0, reasons(end+1)="auditory JND <= 0"; end %#ok<AGROW>
        if isfinite(V_Slope(s)) && V_Slope(s)<=0, reasons(end+1)="visual psychometric slope <= 0"; end %#ok<AGROW>
        if isfinite(A_Slope(s)) && A_Slope(s)<=0, reasons(end+1)="auditory psychometric slope <= 0"; end %#ok<AGROW>

        Included(s)=isempty(reasons);
        if ~Included(s), ExclusionReason(s)=strjoin(reasons,'; '); end
    end

    q=table(ids,V_PSE,V_JND,V_Lapse,V_Slope,A_PSE,A_JND,A_Lapse,A_Slope,Included,ExclusionReason, ...
        'VariableNames',{'ID','V_PSE','V_JND','V_Lapse','V_Slope','A_PSE','A_JND','A_Lapse','A_Slope','Included','ExclusionReason'});
end

function [PSE,lapseRate,JND,slope]=fitPsychometricUnified(ISI,Resp)
    ISI=double(ISI(:)); Resp=double(Resp(:));
    valid=isfinite(ISI)&isfinite(Resp)&ismember(Resp,[0 1]);
    ISI=ISI(valid); Resp=Resp(valid);
    PSE=NaN; lapseRate=NaN; JND=NaN; slope=NaN;
    if numel(ISI)<10 || numel(unique(ISI))<3, return; end
    u=unique(ISI); Y=zeros(numel(u),1); N=zeros(numel(u),1);
    for i=1:numel(u)
        idx=ISI==u(i); Y(i)=sum(Resp(idx)==1); N(i)=sum(idx);
    end
    P=Y./N; lapseRate=(P(1)+(1-P(end)))/2;
    oldWarn=warning; c=onCleanup(@() warning(oldWarn)); %#ok<NASGU>
    warning('off','stats:glmfit:PerfectSeparation');
    warning('off','stats:glmfit:IterationLimit');
    try
        b=glmfit(u,[Y N],'binomial','link','logit');
        slope=b(2);
        if ~isfinite(slope)||abs(slope)<eps, return; end
        PSE=-b(1)/slope;
        JND=log(3)/abs(slope);
        if abs(PSE)>1000 || JND>1000, PSE=NaN; JND=NaN; end
    catch
    end
end

function statsTable=baselineStatistics(q)
    vars={{'PSE',q.V_PSE,q.A_PSE},{'JND',q.V_JND,q.A_JND}};
    rows=cell(0,13);
    for i=1:numel(vars)
        name=vars{i}{1}; v=vars{i}{2}; a=vars{i}{3};
        valid=isfinite(v)&isfinite(a); v=v(valid); a=a(valid); d=v-a;
        if numel(d)>=2
            [~,p,ci,st]=ttest(v,a); dz=mean(d)/std(d);
            rows(end+1,:)={name,numel(d),mean(v),std(v),mean(a),std(a),mean(d),ci(1),ci(2),st.tstat,st.df,p,dz}; %#ok<AGROW>
        else
            rows(end+1,:)={name,numel(d),mean(v,'omitnan'),std(v,'omitnan'),mean(a,'omitnan'),std(a,'omitnan'),NaN,NaN,NaN,NaN,NaN,NaN,NaN}; %#ok<AGROW>
        end
    end
    statsTable=cell2table(rows,'VariableNames',{'Measure','N','VisualMean','VisualSD','AuditoryMean','AuditorySD', ...
        'MeanDifference_VminusA','CI_Lower','CI_Upper','t','df','p','Cohen_dz'});
end

function tbl=addDerivedTrialVariables(tbl,q,lowSlackThresholdMs)
    n=height(tbl);
    zA=nan(n,1); zV=nan(n,1);
    CenteredA=nan(n,1); CenteredV=nan(n,1);
    TargetISI=nan(n,1); DistractorISI=nan(n,1);
    TargetCentered=nan(n,1); DistractorCentered=nan(n,1);
    TargetZ=nan(n,1); DistractorZ=nan(n,1);
    BaselineTargetPSE=nan(n,1);

    qIDs=string(q.ID);
    for s=1:height(q)
        idx=string(tbl.Subject)==qIDs(s);

        if isfinite(q.A_PSE(s))
            CenteredA(idx)=tbl.ISI_A(idx)-q.A_PSE(s);
        end
        if isfinite(q.V_PSE(s))
            CenteredV(idx)=tbl.ISI_V(idx)-q.V_PSE(s);
        end
        if isfinite(q.A_JND(s)) && q.A_JND(s)>0
            zA(idx)=CenteredA(idx)./q.A_JND(s);
        end
        if isfinite(q.V_JND(s)) && q.V_JND(s)>0
            zV(idx)=CenteredV(idx)./q.V_JND(s);
        end

        iv=idx & string(tbl.Task)=="AttendV";
        ia=idx & string(tbl.Task)=="AttendA";

        TargetISI(iv)=tbl.ISI_V(iv);
        DistractorISI(iv)=tbl.ISI_A(iv);
        TargetCentered(iv)=CenteredV(iv);
        DistractorCentered(iv)=CenteredA(iv);
        TargetZ(iv)=zV(iv);
        DistractorZ(iv)=zA(iv);
        BaselineTargetPSE(iv)=q.V_PSE(s);

        TargetISI(ia)=tbl.ISI_A(ia);
        DistractorISI(ia)=tbl.ISI_V(ia);
        TargetCentered(ia)=CenteredA(ia);
        DistractorCentered(ia)=CenteredV(ia);
        TargetZ(ia)=zA(ia);
        DistractorZ(ia)=zV(ia);
        BaselineTargetPSE(ia)=q.A_PSE(s);
    end

    tbl.CenteredA=CenteredA; tbl.CenteredV=CenteredV;
    tbl.zA=zA; tbl.zV=zV;

    tbl.AbsRawDiff=abs(tbl.ISI_A-tbl.ISI_V);
    tbl.MeanRaw=(tbl.ISI_A+tbl.ISI_V)/2;

    tbl.AbsPSECenteredDiff=abs(CenteredA-CenteredV);
    tbl.MeanPSECentered=(CenteredA+CenteredV)/2;

    tbl.AbsPerceptualDiff=abs(zA-zV);
    tbl.MeanPerceptual=(zA+zV)/2;

    tbl.TargetISI=TargetISI; tbl.DistractorISI=DistractorISI;
    tbl.TargetCentered=TargetCentered; tbl.DistractorCentered=DistractorCentered;
    tbl.TargetZ=TargetZ; tbl.DistractorZ=DistractorZ;
    tbl.BaselineTargetPSE=BaselineTargetPSE;

    % Code-level requested scheduling geometry from playStimuli_AV.m.
    % These are NOT treated as measured physical onset times.
    tbl.V1OffsetFromAudioMs=(100+tbl.ISI_A-tbl.ISI_V)/2;
    av=ismember(string(tbl.Task),["AttendV","AttendA"]);
    tbl.CodeTimingRisk=av & tbl.V1OffsetFromAudioMs<=0;
    tbl.LowTimingSlack=av & tbl.V1OffsetFromAudioMs>0 & ...
        tbl.V1OffsetFromAudioMs<=lowSlackThresholdMs;

    % Symmetric robustness scope: removes BOTH extreme-disparity triangles.
    % This avoids comparing an asymmetric 43-cell grid with the full grid.
    tbl.SymmetricCore90=av & tbl.AbsRawDiff<=90;

    tbl.TimingGeometry=strings(n,1);
    tbl.TimingGeometry(av & (tbl.ISI_V-tbl.ISI_A)>=120)="CodeRisk";
    tbl.TimingGeometry(av & (tbl.ISI_A-tbl.ISI_V)>=120)="MirrorExtreme";
    tbl.TimingGeometry(av & tbl.AbsRawDiff<=90)="SymmetricCore";
end

function heat=buildHeatmapTable(tbl)
    levels=30:30:210; tasks=["AttendV","AttendA"]; responses=["Motion","Causal"];
    rows=cell(0,8);
    for it=1:numel(tasks)
        for ia=1:numel(levels)
            for iv=1:numel(levels)
                cellMask=string(tbl.Task)==tasks(it)&tbl.ISI_A==levels(ia)&tbl.ISI_V==levels(iv);
                for ir=1:numel(responses)
                    if responses(ir)=="Motion", y=tbl.RespMotion; else, y=tbl.RespCausal; end
                    ids=unique(string(tbl.Subject(cellMask & isfinite(y)))); sm=nan(numel(ids),1);
                    for s=1:numel(ids)
                        idx=cellMask & string(tbl.Subject)==ids(s) & isfinite(y);
                        sm(s)=mean(y(idx));
                    end
                    sm=sm(isfinite(sm));
                    if isempty(sm), gm=NaN; se=NaN; ns=0; else, gm=mean(sm); se=std(sm)/sqrt(numel(sm)); ns=numel(sm); end
                    rows(end+1,:)={char(tasks(it)),char(responses(ir)),levels(ia),levels(iv),gm,se,ns,sum(cellMask & isfinite(y))}; %#ok<AGROW>
                end
            end
        end
    end
    heat=cell2table(rows,'VariableNames',{'Task','Response','ISI_A','ISI_V','GroupMean','SE','NSubjects','NTrials'});
end

function fig=plotAVHeatmaps(heat)
    levels=30:30:210; tasks={'AttendV','AttendA'}; responses={'Motion','Causal'};
    fig=figure('Color','w','Position',[80 80 950 760]);
    tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    for r=1:2
        for t=1:2
            nexttile; M=nan(7,7);
            d=heat(strcmp(heat.Task,tasks{t})&strcmp(heat.Response,responses{r}),:);
            for i=1:height(d)
                ia=find(levels==d.ISI_A(i),1); iv=find(levels==d.ISI_V(i),1);
                if ~isempty(ia)&&~isempty(iv), M(ia,iv)=d.GroupMean(i); end
            end
            imagesc(levels,levels,M,[0 1]); axis xy equal tight; colorbar;
            xlabel('Visual ISI (ms)'); ylabel('Auditory ISI (ms)');
            if r==1, respTitle='P(group motion)'; else, respTitle='P(common source)'; end
            title(sprintf('%s | %s',tasks{t},respTitle),'Interpreter','none');
        end
    end
end

function [coefAll,coordComp,objects]=runBehaviorGLMEs(tbl)
    % All inferential analyses use the complete 7x7 audiovisual design.
    scopes={"Full"}; coefAll=table(); compRows=cell(0,8); objects=struct();
    for is=1:numel(scopes)
        d=tbl(ismember(string(tbl.Task),["AttendV","AttendA"]),:);
        d.Task=categorical(string(d.Task),{'AttendV','AttendA'});
        d.Subject=categorical(string(d.Subject));
        d.DirectionCat=categorical(d.Direction);
        d.Target30C=(d.TargetISI-120)/30;
        d.Distractor30C=(d.DistractorISI-120)/30;
        d.AbsDiff30=d.AbsRawDiff/30;

        % Motion model: target and distractor evidence, attention interaction, direction control.
        dm=d(isfinite(d.RespMotion)&isfinite(d.Target30C)&isfinite(d.Distractor30C),:);
        try
            mMotion=fitglme(dm,'RespMotion ~ Target30C*Task + Distractor30C*Task + DirectionCat + (1|Subject)', ...
                'Distribution','Binomial','Link','logit','FitMethod','Laplace');
            c=glmeCoefficientTable(mMotion,scopes{is},"Motion","TargetDistractor"); coefAll=[coefAll;c]; %#ok<AGROW>
            objects.(char(scopes{is})).Motion=mMotion;
        catch ME
            warning('Motion GLME failed (%s): %s',scopes{is},ME.message);
        end

        % Explicit causal judgment: raw-ms disparity.
        dc=d(isfinite(d.RespCausal)&isfinite(d.AbsDiff30),:);
        try
            mRaw=fitglme(dc,'RespCausal ~ AbsDiff30*Task + DirectionCat + (1|Subject)', ...
                'Distribution','Binomial','Link','logit','FitMethod','Laplace');
            c=glmeCoefficientTable(mRaw,scopes{is},"Causal","RawMilliseconds"); coefAll=[coefAll;c]; %#ok<AGROW>
            objects.(char(scopes{is})).CausalRaw=mRaw;
            [aic,bic,ll]=modelCriteria(mRaw);
            compRows(end+1,:)={char(scopes{is}),'RawMilliseconds',height(dc),numel(unique(dc.Subject)),aic,bic,ll,'abs(ISI_A-ISI_V)/30'}; %#ok<AGROW>
        catch ME
            warning('Raw causal GLME failed (%s): %s',scopes{is},ME.message);
        end

        % Explicit causal judgment: participant-normalized perceptual disparity.
        dp=d(isfinite(d.RespCausal)&isfinite(d.AbsPerceptualDiff),:);
        try
            mPer=fitglme(dp,'RespCausal ~ AbsPerceptualDiff*Task + DirectionCat + (1|Subject)', ...
                'Distribution','Binomial','Link','logit','FitMethod','Laplace');
            c=glmeCoefficientTable(mPer,scopes{is},"Causal","PerceptualPSEJND"); coefAll=[coefAll;c]; %#ok<AGROW>
            objects.(char(scopes{is})).CausalPerceptual=mPer;
            [aic,bic,ll]=modelCriteria(mPer);
            compRows(end+1,:)={char(scopes{is}),'PerceptualPSEJND',height(dp),numel(unique(dp.Subject)),aic,bic,ll,'abs(zA-zV)'}; %#ok<AGROW>
        catch ME
            warning('Perceptual causal GLME failed (%s): %s',scopes{is},ME.message);
        end
    end
    coordComp=cell2table(compRows,'VariableNames',{'Scope','Coordinate','NTrials','NSubjects','AIC','BIC','LogLikelihood','Predictor'});
end

function out=glmeCoefficientTable(mdl,scope,outcome,coordinate)
    c=mdl.Coefficients; ci=coefCI(mdl);
    out=table(repmat(string(scope),height(c),1),repmat(string(outcome),height(c),1), ...
        repmat(string(coordinate),height(c),1),string(c.Name),c.Estimate,c.SE,c.tStat,c.DF,c.pValue, ...
        ci(:,1),ci(:,2),exp(c.Estimate),exp(ci(:,1)),exp(ci(:,2)), ...
        'VariableNames',{'Scope','Outcome','Coordinate','Term','Beta','SE','Statistic','DF','p','CI_Lower','CI_Upper','OddsRatio','OR_CI_Lower','OR_CI_Upper'});
end

function [aic,bic,ll]=modelCriteria(m)
    aic=NaN; bic=NaN; ll=NaN;
    try, aic=m.ModelCriterion.AIC; catch, end
    try, bic=m.ModelCriterion.BIC; catch, end
    try, ll=m.LogLikelihood; catch, end
end


function [coefAll,causalComp,motionComp,baselineCoef,objects] = ...
    runPhase1bAnalyses(tbl,q,primaryIDs,completeIDs)
% Phase-1b is deliberately run BEFORE BCI fitting.
% Goals:
%  1) compare raw, PSE-centered-ms, and PSE/JND-normalized coordinates
%     using the complete 7x7 audiovisual design;
%  2) determine whether attention effects remain after subject-specific
%     baseline alignment;
%  3) check the small direction effect;
%  4) repeat key results in the complete-design sample so that the
%     primary QC cutoff is not the sole basis of inference.
% No audiovisual condition is removed in this function.

    sampleNames={"PrimaryQC","CompleteDesign"};
    sampleIDs={string(primaryIDs(:)),string(completeIDs(:))};
    scopeNames={"Full"};

    coefAll=table();
    causalRows=cell(0,11);
    motionRows=cell(0,11);
    baselineCoef=table();
    objects=struct();

    for isamp=1:numel(sampleNames)
        sidList=sampleIDs{isamp};
        base=tbl(ismember(string(tbl.Subject),sidList),:);

        % ---------- baseline direction / modality check ----------
        db=base(ismember(string(base.Task),["BaselineV","BaselineA"]) & ...
            isfinite(base.RespMotion) & isfinite(base.Direction),:);
        if ~isempty(db)
            db.Subject=categorical(string(db.Subject));
            modText=strings(height(db),1);
            modText(string(db.Task)=="BaselineV")="Visual";
            modText(string(db.Task)=="BaselineA")="Auditory";
            db.Modality=categorical(modText,{'Visual','Auditory'});
            db.DirectionCat=categorical(db.Direction);
            db.ISIBase=nan(height(db),1);
            db.ISIBase(string(db.Task)=="BaselineV")=db.ISI_V(string(db.Task)=="BaselineV");
            db.ISIBase(string(db.Task)=="BaselineA")=db.ISI_A(string(db.Task)=="BaselineA");
            db.ISI30C=(db.ISIBase-120)/30;

            [mBase,rsBase]=fitBaselineDirectionModel(db);
            cb=glmeCoefficientTablePhase1b(mBase,sampleNames{isamp},"Baseline","RawMilliseconds","Full",rsBase);
            baselineCoef=[baselineCoef;cb]; %#ok<AGROW>
            objects.(char(sampleNames{isamp})).BaselineDirection=mBase;
        end

        for isc=1:numel(scopeNames)
            d=base(ismember(string(base.Task),["AttendV","AttendA"]),:);
            if isempty(d), continue; end

            d.Task=categorical(string(d.Task),{'AttendV','AttendA'});
            d.Subject=categorical(string(d.Subject));
            d.DirectionCat=categorical(d.Direction);

            % ==========================================================
            % MOTION: coordinate comparison with IDENTICAL random effects
            % ==========================================================
            coordNames={"RawMilliseconds","PSECenteredMilliseconds","PerceptualPSEJND"};
            for ic=1:numel(coordNames)
                dm=d(isfinite(d.RespMotion),:);
                switch coordNames{ic}
                    case "RawMilliseconds"
                        dm.XTarget=(dm.TargetISI-120)/30;
                        dm.XDistractor=(dm.DistractorISI-120)/30;
                        predictorText='target/distractor raw ISI (30-ms units)';
                    case "PSECenteredMilliseconds"
                        dm.XTarget=dm.TargetCentered/30;
                        dm.XDistractor=dm.DistractorCentered/30;
                        predictorText='target/distractor (ISI-PSE), 30-ms units';
                    case "PerceptualPSEJND"
                        dm.XTarget=dm.TargetZ;
                        dm.XDistractor=dm.DistractorZ;
                        predictorText='target/distractor PSE/JND z coordinates';
                end
                dm=dm(isfinite(dm.XTarget)&isfinite(dm.XDistractor),:);
                if isempty(dm), continue; end

                % Random intercept is intentionally used for AIC/BIC
                % coordinate comparison so all three models have the same
                % random-effects structure.
                m=fitglme(dm, ...
                    'RespMotion ~ XTarget*Task + XDistractor*Task + DirectionCat + (1|Subject)', ...
                    'Distribution','Binomial','Link','logit','FitMethod','Laplace');
                [aic,bic,ll]=modelCriteria(m);
                motionRows(end+1,:)={sampleNames{isamp},scopeNames{isc},coordNames{ic}, ...
                    height(dm),numel(unique(dm.Subject)),aic,bic,ll,predictorText, ...
                    'Random intercept','Motion'}; %#ok<AGROW>
                motionField = ['Motion_' char(coordNames{ic})];
                objects.(char(sampleNames{isamp})).(char(scopeNames{isc})).(motionField)=m;

                % Preserve coefficients too; the normalized model is the
                % clearest inferential readout after baseline alignment.
                cc=glmeCoefficientTablePhase1b(m,sampleNames{isamp},"Motion",coordNames{ic}, ...
                    scopeNames{isc},"Random intercept");
                coefAll=[coefAll;cc]; %#ok<AGROW>
            end

            % ==========================================================
            % CAUSAL: disparity + mean level; equal model complexity
            % ==========================================================
            for ic=1:numel(coordNames)
                dc=d(isfinite(d.RespCausal),:);
                switch coordNames{ic}
                    case "RawMilliseconds"
                        dc.DCoord=dc.AbsRawDiff/30;
                        dc.MCoord=(dc.MeanRaw-120)/30;
                        predictorText='|A-V| and mean(A,V), raw 30-ms units';
                    case "PSECenteredMilliseconds"
                        dc.DCoord=dc.AbsPSECenteredDiff/30;
                        dc.MCoord=dc.MeanPSECentered/30;
                        predictorText='PSE-centered disparity and mean, 30-ms units';
                    case "PerceptualPSEJND"
                        dc.DCoord=dc.AbsPerceptualDiff;
                        dc.MCoord=dc.MeanPerceptual;
                        predictorText='PSE/JND disparity and mean';
                end
                dc=dc(isfinite(dc.DCoord)&isfinite(dc.MCoord),:);
                if isempty(dc), continue; end

                m=fitglme(dc, ...
                    'RespCausal ~ DCoord*Task + MCoord*Task + DirectionCat + (1|Subject)', ...
                    'Distribution','Binomial','Link','logit','FitMethod','Laplace');
                [aic,bic,ll]=modelCriteria(m);
                causalRows(end+1,:)={sampleNames{isamp},scopeNames{isc},coordNames{ic}, ...
                    height(dc),numel(unique(dc.Subject)),aic,bic,ll,predictorText, ...
                    'Random intercept','Causal'}; %#ok<AGROW>
                causalField = ['Causal_' char(coordNames{ic})];
                objects.(char(sampleNames{isamp})).(char(scopeNames{isc})).(causalField)=m;
                cc=glmeCoefficientTablePhase1b(m,sampleNames{isamp},"Causal",coordNames{ic}, ...
                    scopeNames{isc},"Random intercept");
                coefAll=[coefAll;cc]; %#ok<AGROW>
            end

            % ==========================================================
            % Preferred inferential motion model: PSE/JND normalized,
            % with subject random slopes when MATLAB can estimate them.
            % ==========================================================
            dn=d(isfinite(d.RespMotion)&isfinite(d.TargetZ)&isfinite(d.DistractorZ),:);
            if ~isempty(dn)
                dn.XTarget=dn.TargetZ; dn.XDistractor=dn.DistractorZ;
                [mNorm,rsNorm]=fitMotionRandomSlopeModel(dn);
                cc=glmeCoefficientTablePhase1b(mNorm,sampleNames{isamp}, ...
                    "MotionRandomSlope","PerceptualPSEJND",scopeNames{isc},rsNorm);
                coefAll=[coefAll;cc]; %#ok<AGROW>
                objects.(char(sampleNames{isamp})).(char(scopeNames{isc})).MotionNormalizedRandomSlope=mNorm;
            end
        end
    end

    causalComp=cell2table(causalRows,'VariableNames', ...
        {'Sample','Scope','Coordinate','NTrials','NSubjects','AIC','BIC','LogLikelihood', ...
         'Predictor','RandomStructure','Outcome'});
    motionComp=cell2table(motionRows,'VariableNames', ...
        {'Sample','Scope','Coordinate','NTrials','NSubjects','AIC','BIC','LogLikelihood', ...
         'Predictor','RandomStructure','Outcome'});

end

function [mdl,label]=fitMotionRandomSlopeModel(d)
    try
        mdl=fitglme(d, ...
            'RespMotion ~ XTarget*Task + XDistractor*Task + DirectionCat + (1 + XTarget + XDistractor|Subject)', ...
            'Distribution','Binomial','Link','logit','FitMethod','Laplace');
        label="Random intercept + target/distractor slopes";
    catch ME
        warning('Motion random-slope GLME failed; using random intercept. %s',ME.message);
        mdl=fitglme(d, ...
            'RespMotion ~ XTarget*Task + XDistractor*Task + DirectionCat + (1|Subject)', ...
            'Distribution','Binomial','Link','logit','FitMethod','Laplace');
        label="Random intercept fallback";
    end
end

function [mdl,label]=fitBaselineDirectionModel(d)
    try
        mdl=fitglme(d, ...
            'RespMotion ~ ISI30C*Modality + DirectionCat*Modality + (1 + ISI30C|Subject)', ...
            'Distribution','Binomial','Link','logit','FitMethod','Laplace');
        label="Random intercept + ISI slope";
    catch ME
        warning('Baseline direction random-slope GLME failed; using random intercept. %s',ME.message);
        mdl=fitglme(d, ...
            'RespMotion ~ ISI30C*Modality + DirectionCat*Modality + (1|Subject)', ...
            'Distribution','Binomial','Link','logit','FitMethod','Laplace');
        label="Random intercept fallback";
    end
end

function out=glmeCoefficientTablePhase1b(mdl,sample,outcome,coordinate,scope,randomStructure)
    c=mdl.Coefficients; ci=coefCI(mdl);
    out=table(repmat(string(sample),height(c),1),repmat(string(scope),height(c),1), ...
        repmat(string(outcome),height(c),1),repmat(string(coordinate),height(c),1), ...
        repmat(string(randomStructure),height(c),1),string(c.Name), ...
        c.Estimate,c.SE,c.tStat,c.DF,c.pValue,ci(:,1),ci(:,2), ...
        exp(c.Estimate),exp(ci(:,1)),exp(ci(:,2)), ...
        'VariableNames',{'Sample','Scope','Outcome','Coordinate','RandomStructure', ...
        'Term','Beta','SE','Statistic','DF','p','CI_Lower','CI_Upper', ...
        'OddsRatio','OR_CI_Lower','OR_CI_Upper'});
end

function appendPhase1bSummary(path,causalComp,motionComp,coef,baselineCoef)
    fid=fopen(path,'a'); if fid<0, error('Cannot append %s',path); end
    c=onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid,'\n\n============================================================\n');
    fprintf(fid,'PHASE-1B RESULTS (added after review of the first run)\n');
    fprintf(fid,'============================================================\n');
    fprintf(fid,'8) CAUSAL COORDINATE COMPARISON: raw vs PSE-centered vs PSE/JND (full 7x7 grid only)\n');
    fprintf(fid,'%s\n',evalc('disp(causalComp)'));
    fprintf(fid,'9) MOTION COORDINATE COMPARISON (full 7x7 grid only)\n%s\n',evalc('disp(motionComp)'));
    fprintf(fid,'10) PRIMARY-QC / FULL-GRID NORMALIZED MOTION COEFFICIENTS\n');
    x=coef(coef.Sample=="PrimaryQC" & coef.Scope=="Full" & ...
        coef.Outcome=="MotionRandomSlope" & coef.Coordinate=="PerceptualPSEJND",:);
    fprintf(fid,'%s\n',evalc('disp(x)'));
    fprintf(fid,'11) COMPLETE-DESIGN / FULL-GRID NORMALIZED MOTION COEFFICIENTS\n');
    x=coef(coef.Sample=="CompleteDesign" & coef.Scope=="Full" & ...
        coef.Outcome=="MotionRandomSlope" & coef.Coordinate=="PerceptualPSEJND",:);
    fprintf(fid,'%s\n',evalc('disp(x)'));
    fprintf(fid,'12) BASELINE DIRECTION CHECK\n%s\n',evalc('disp(baselineCoef)'));
end

function [fits,evidence]=fitBCIModels(tbl,q,nSim,nStarts,coordModes,timingScopes,modelCodes,modelNames,modelK)
    includedIDs=string(q.ID(q.Included));
    taskDefs=struct('task',{'AttendV','AttendA'},'modelTask',{'Attend_V','Attend_A'});
    fitRows=cell(0,18); evRows=cell(0,9);
    optimOptions=optimset('MaxIter',1500,'MaxFunEvals',8000,'Display','off','TolFun',1e-4,'TolX',1e-4);

    for ic=1:numel(coordModes)
        coord=coordModes{ic};
        for iscope=1:numel(timingScopes)
            scope=timingScopes{iscope};
            for it=1:numel(taskDefs)
                bicMat=nan(numel(includedIDs),numel(modelCodes));
                for s=1:numel(includedIDs)
                    sid=includedIDs(s); qIdx=find(string(q.ID)==sid,1);
                    d=tbl(string(tbl.Subject)==sid & string(tbl.Task)==taskDefs(it).task,:);
                    d=d(isfinite(d.RespMotion)&isfinite(d.ISI_A)&isfinite(d.ISI_V),:);
                    if isempty(d), continue; end

                    switch coord
                        case 'raw'
                            sAtrial=d.ISI_A; sVtrial=d.ISI_V;
                            [LB,UB,start0]=rawBounds(q,qIdx,taskDefs(it).task);
                        case 'pse_centered'
                            sAtrial=d.CenteredA; sVtrial=d.CenteredV;
                            good=isfinite(sAtrial)&isfinite(sVtrial);
                            d=d(good,:); sAtrial=sAtrial(good); sVtrial=sVtrial(good);
                            [LB,UB,start0]=pseCenteredBounds();
                        case 'perceptual'
                            sAtrial=d.zA; sVtrial=d.zV;
                            good=isfinite(sAtrial)&isfinite(sVtrial);
                            d=d(good,:); sAtrial=sAtrial(good); sVtrial=sVtrial(good);
                            [LB,UB,start0]=perceptualBounds();
                        otherwise, error('Unknown coordinate mode %s',coord);
                    end
                    nominal=[d.ISI_A,d.ISI_V]; [~,~,g]=unique(nominal,'rows'); nCond=max(g);
                    counts=zeros(nCond,2); sA=zeros(nCond,1); sV=zeros(nCond,1);
                    for c=1:nCond
                        idx=g==c; counts(c,:)=[sum(d.RespMotion(idx)==0),sum(d.RespMotion(idx)==1)];
                        sA(c)=mean(sAtrial(idx)); sV(c)=mean(sVtrial(idx));
                    end
                    nTrials=sum(counts,'all');
                    localSeed=100000*ic+10000*iscope+1000*it+s;
                    old=rng; rng(localSeed,'twister'); xAPre=randn(nCond,nSim); xVPre=randn(nCond,nSim); rng(old);

                    for im=1:numel(modelCodes)
                        code=modelCodes(im); param=struct('iModel',code,'taskName',taskDefs(it).modelTask, ...
                            'sA',repmat(sA,1,nSim),'sV',repmat(sV,1,nSim),'xAPre',xAPre,'xVPre',xVPre,'dataCounts',counts);
                        freeMask=true(1,6); fixedPhi=nan(1,6);
                        if code==4, freeMask(1)=false; fixedPhi(1)=1; elseif code==5, freeMask(1)=false; fixedPhi(1)=0; end
                        param.freeMask=freeMask; param.fixedPhi=fixedPhi;
                        bestNLL=inf; bestPhi=nan(1,6);
                        for st=1:nStarts
                            if st==1, x0full=start0; else, x0full=LB+rand(1,6).*(UB-LB); end
                            if code~=1, x0full(1)=fixedPhi(1); end
                            [xhat,nll]=boundedFminsearch(@(x) computeNegLL_AVTernus_v4(x,param), ...
                                x0full(freeMask),LB(freeMask),UB(freeMask),optimOptions);
                            if isfinite(nll)&&nll<bestNLL
                                bestNLL=nll; tmp=fixedPhi; tmp(freeMask)=xhat; bestPhi=tmp;
                            end
                        end
                        LLK=-bestNLL; k=modelK(im); AIC=2*bestNLL+2*k; BIC=2*bestNLL+k*log(nTrials); bicMat(s,im)=BIC;
                        fitRows(end+1,:)={char(sid),coord,scope,taskDefs(it).task,modelNames{im},nTrials,nCond,LLK,AIC,BIC,k, ...
                            bestPhi(1),bestPhi(2),bestPhi(3),bestPhi(4),bestPhi(5),bestPhi(6),bestNLL}; %#ok<AGROW>
                    end
                end
                valid=all(isfinite(bicMat),2); sumBIC=sum(bicMat(valid,:),1);
                if any(valid)
                    delta=sumBIC-min(sumBIC); w=exp(-0.5*delta); w=w/sum(w);
                else, w=nan(1,numel(modelCodes)); end
                pxp=nan(1,numel(modelCodes));
                if sum(valid)>=2 && exist('spm_BMS','file')==2
                    try, [~,~,~,pxp]=spm_BMS(-0.5*bicMat(valid,:)); pxp=reshape(pxp,1,[]); catch, end
                end
                for im=1:numel(modelCodes)
                    evRows(end+1,:)={coord,scope,taskDefs(it).task,modelNames{im},sum(valid),sumBIC(im),w(im),pxp(im),modelK(im)}; %#ok<AGROW>
                end
            end
        end
    end
    fits=cell2table(fitRows,'VariableNames',{'Subject','Coordinate','TimingScope','Task','Model','NTrials','NConditions','LLK','AIC','BIC','K', ...
        'pCommon','muP','sigP','sigA','sigV','Criterion','NegLL'});
    evidence=cell2table(evRows,'VariableNames',{'Coordinate','TimingScope','Task','Model','NSubjects','SumBIC','BICWeight','PXP','K'});
end

function [xBest,fBest]=boundedFminsearch(fun,x0,lb,ub,options)
    x0=double(x0(:)'); lb=double(lb(:)'); ub=double(ub(:)');
    if any(~isfinite(lb))||any(~isfinite(ub))||any(ub<=lb), error('boundedFminsearch requires finite LB < UB.'); end
    margin=max(1e-10,1e-8*(ub-lb)); x0=min(max(x0,lb+margin),ub-margin);
    ratio=(x0-lb)./(ub-x0); y0=log(ratio);
    transform=@(y) lb+(ub-lb)./(1+exp(-min(max(y,-50),50)));
    [yBest,fBest]=fminsearch(@(y) fun(transform(y)),y0,options);
    xBest=transform(yBest);
end

function [LB,UB,start0]=rawBounds(q,qIdx,task)
    LB=[0.001,0,1,1,1,0]; UB=[0.999,300,250,250,250,300];
    if strcmp(task,'AttendA'), crit0=q.A_PSE(qIdx); else, crit0=q.V_PSE(qIdx); end
    mu0=mean([q.A_PSE(qIdx),q.V_PSE(qIdx)],'omitnan');
    if ~isfinite(mu0),mu0=120;end; if ~isfinite(crit0),crit0=120;end
    start0=[0.5,mu0,60,30,30,crit0]; start0=min(max(start0,LB),UB);
end

function [LB,UB,start0]=pseCenteredBounds()
    % PSE-centered coordinates remain in milliseconds, so sensory noise is
    % still estimated in interpretable ms units rather than divided out.
    LB=[0.001,-180,1,1,1,-180];
    UB=[0.999,180,250,250,250,180];
    start0=[0.5,0,60,30,30,0];
end

function [LB,UB,start0]=perceptualBounds()
    LB=[0.001,-4,0.05,0.05,0.05,-4]; UB=[0.999,4,6,6,6,4]; start0=[0.5,0,1.5,1,1,0];
end

function fig=plotBaselineFigure(q)
    fig=figure('Color','w','Position',[100 100 900 420]); tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
    data={{q.V_PSE,q.A_PSE,'PSE (ms)'},{q.V_JND,q.A_JND,'JND (ms)'}};
    for i=1:2
        nexttile; hold on; v=data{i}{1}; a=data{i}{2}; valid=isfinite(v)&isfinite(a); v=v(valid); a=a(valid);
        if ~isempty(v), plot([1 2],[v a]','-o','Color',[.75 .75 .75],'MarkerFaceColor','w','MarkerSize',4); end
        if numel(v)>=1
            m=[mean(v),mean(a)]; se=[std(v)/sqrt(max(1,numel(v))),std(a)/sqrt(max(1,numel(a)))];
            bar([1 2],m,.55,'FaceAlpha',.5,'EdgeColor','none'); errorbar([1 2],m,se,'k','LineStyle','none','LineWidth',1.3);
        end
        xticks([1 2]); xticklabels({'Visual','Auditory'}); xlim([.5 2.5]); ylabel(data{i}{3}); box off; grid on;
    end
end

function saveFigure(fig,path)
    try, exportgraphics(fig,path,'Resolution',300); catch, saveas(fig,path); end
end

function writeKeySummary(path,fileAudit,subjectAudit,q,baseStats,timingAudit,coef,coordComp,ranBCI,bciEvidence)
    fid=fopen(path,'w'); if fid<0, error('Cannot write %s',path); end; c=onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid,'Audiovisual Ternus v4 - KEY RESULTS TO PASTE\n');
    fprintf(fid,'Generated: %s\n\n',datestr(now));
    fprintf(fid,'1) DATA / SAMPLE\n');
    fprintf(fid,'Complete files found = %d\n',height(fileAudit));
    fprintf(fid,'Participants discovered = %d\n',height(subjectAudit));
    fprintf(fid,'Complete programmed design = %d\n',sum(subjectAudit.CompleteDesign));
    fprintf(fid,'Primary QC included = %d\n',sum(q.Included));
    fprintf(fid,'Primary QC excluded = %d\n\n',sum(~q.Included));
    if any(~q.Included)
        fprintf(fid,'Excluded/flagged subjects and reasons:\n%s\n',evalc('disp(q(~q.Included,{''ID'',''ExclusionReason''}))'));
    end
    fprintf(fid,'2) BASELINE PSE/JND\n%s\n',evalc('disp(baseStats)'));
    fprintf(fid,'3) CODE-LEVEL TIMING AUDIT (descriptive only; no conditions are excluded)\n');
    fprintf(fid,'Risk cells (V1 target <= audio onset) = %d / %d\n',sum(timingAudit.CodeTimingRisk),height(timingAudit));
    fprintf(fid,'Low-slack cells = %d\n\n',sum(timingAudit.LowSlack));
    fprintf(fid,'4) CAUSAL COORDINATE COMPARISON (raw ms vs PSE/JND-normalized)\n%s\n',evalc('disp(coordComp)'));
    fprintf(fid,'5) FULL-SCOPE MOTION GLME COEFFICIENTS\n');
    x=coef(coef.Scope=="Full" & coef.Outcome=="Motion",:); fprintf(fid,'%s\n',evalc('disp(x)'));
    fprintf(fid,'6) FULL-SCOPE CAUSAL GLME COEFFICIENTS\n');
    x=coef(coef.Scope=="Full" & coef.Outcome=="Causal",:); fprintf(fid,'%s\n',evalc('disp(x)'));
    fprintf(fid,'7) BCI MODELS RUN = %d\n',ranBCI);
    if ranBCI && ~isempty(bciEvidence), fprintf(fid,'%s\n',evalc('disp(bciEvidence)')); end
end

function sx=normalizeTextColumn(x)
    if isstring(x), sx=x(:);
    elseif iscategorical(x), sx=string(x(:));
    elseif ischar(x), if isrow(x),sx=string({x});else,sx=string(cellstr(x));end; sx=sx(:);
    elseif iscell(x)
        sx=strings(numel(x),1);
        for ii=1:numel(x)
            v=x{ii}; while iscell(v)&&isscalar(v),v=v{1};end
            if isempty(v),continue;elseif ischar(v)||isstring(v)||iscategorical(v),tmp=string(v);tmp=tmp(:);tmp=tmp(~ismissing(tmp)&strlength(tmp)>0);if ~isempty(tmp),sx(ii)=tmp(1);end
            elseif isnumeric(v)||islogical(v),if isscalar(v)&&isfinite(double(v)),sx(ii)=string(v);end
            end
        end
    else, sx=string(x(:));
    end
    sx=lower(strtrim(sx)); sx(ismissing(sx))="";
end

function y=decodeBinaryStrict(x,posTokens,negTokens)
    if isnumeric(x)||islogical(x)
        y=double(x(:)); y(~ismember(y,[0 1]))=NaN; return;
    end
    sx=normalizeTextColumn(x); pos=lower(strtrim(string(posTokens(:)))); neg=lower(strtrim(string(negTokens(:))));
    y=nan(numel(sx),1); nonempty=strlength(sx)>0;
    y(nonempty&ismember(sx,pos))=1; y(nonempty&ismember(sx,neg))=0;
    unknown=nonempty&isnan(y);
    if any(unknown), warning('Unknown non-empty response tokens converted to NaN: %s',strjoin(cellstr(unique(sx(unknown))),', ')); end
end

function y=toDoubleColumn(x)
    if isnumeric(x)||islogical(x), y=double(x(:)); return; end
    if iscell(x)
        y=nan(numel(x),1); for i=1:numel(x),v=x{i};while iscell(v)&&isscalar(v),v=v{1};end;if isnumeric(v)&&isscalar(v),y(i)=double(v);elseif ischar(v)||isstring(v),y(i)=str2double(string(v));end;end
    else, y=str2double(string(x(:)));
    end
end

function k=getMapKey(P,fieldName)
    k="";
    if isfield(P,'keyMap') && isfield(P.keyMap,fieldName)
        v=P.keyMap.(fieldName); if iscell(v)&&isscalar(v),v=v{1};end; k=lower(strtrim(string(v)));
    end
end
