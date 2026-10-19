%% export_behavior_prediction_grids_v3.m
% Publication-ready fixed-effect prediction grids for Figure 2.
%
% This script DOES NOT refit the GLMEs and DOES NOT change any statistical
% analysis. It reads the already-saved random-slope fixed-effect estimates
% and converts them into intuitive population-level prediction curves.
%
% Required existing files (located recursively under ROOT):
%   Baseline_Psychometric_Summary.csv
%   RealData_AllFits.csv
%   Reliability_RandomSlope_Coefficients.csv
%
% Outputs:
%   Figure2A_Causal_TaskPredictions.csv
%   Figure2B_Causal_ReliabilityPredictions.csv
%   Figure2C_Motion_ReliabilityPredictions.csv
%   Figure2_Prediction_Metadata.txt
%
% Definitions reproduced from the completed reliability analysis:
%   LogJointPrecision = log(1 / (JND_A^2 + JND_V^2))
%   RelBalance        = log(precision_A / precision_V)
%                     = log((JND_V / JND_A)^2)
% Centered predictors subtract the mean of the N=34 primary sample.
%
% For the causal plot, random effects are set to zero and predictions are
% averaged over Direction 1 and 2. Figure 2A uses mean-centered reliability.
% Figure 2B shows the 25th vs 75th empirical percentiles of joint precision
% and averages over AttendV/AttendA because Task x disparity was negligible.
%
% For motion, Figure 2C reports the change in predicted P(group) produced by
% a +30-ms shift in either the target or distractor coordinate, evaluated
% around Target=Distractor=0. The x-axis is the baseline
% distractor-to-target precision ratio, which has the same interpretation
% in AttendV and AttendA.
%
% Authoring principle:
%   These curves are visualizations of the already-estimated GLME fixed
%   effects; they are NOT new hypothesis tests.

clear; clc;

ROOT = 'C:\MSI\oscillation\ternus AV BCI\analysis0906';
OUT_DIR = fullfile(ROOT,'Publication_Figures_v1');
if ~exist(OUT_DIR,'dir'), mkdir(OUT_DIR); end

baselineFile = findOne(ROOT,'Baseline_Psychometric_Summary.csv');
allFitsFile  = findOne(ROOT,'RealData_AllFits.csv');
coefFile     = findOne(ROOT,'Reliability_RandomSlope_Coefficients.csv');

fprintf('Using:\n  %s\n  %s\n  %s\n\n', baselineFile, allFitsFile, coefFile);

B = readtable(baselineFile,'TextType','string');
F = readtable(allFitsFile,'TextType','string');
C = readtable(coefFile,'TextType','string');

% ---- Primary N=34 sample is defined by the completed real-data fit table.
% Most IDs are identical across files, but one historical export shortened
% S06LY to S06. Match by the stable numeric subject prefix (e.g., S06)
% rather than by the full display ID.
baselineKey = subjectKey(B.ID);
fitKey      = subjectKey(F.Subject);
primaryKeys = unique(fitKey,'stable');

keep = ismember(baselineKey,primaryKeys);
B = B(keep,:);

if height(B) ~= numel(primaryKeys)
    missingKeys = setdiff(primaryKeys,subjectKey(B.ID));
    error(['Primary-sample matching failed. Expected %d participants, found %d. ' ...
           'Missing subject keys: %s'], ...
           numel(primaryKeys),height(B),strjoin(cellstr(missingKeys),', '));
end
if height(B) ~= 34
    error('Expected 34 primary participants after key matching; found %d.',height(B));
end

% Audit the one-to-one match and verify that baseline JNDs agree with the
% values saved in the real-data fit table. This catches accidental ID joins.
matchRows = cell(height(B),5);
for ii = 1:height(B)
    key = subjectKey(B.ID(ii));
    z = F(fitKey==key,:);
    matchRows(ii,:) = {char(B.ID(ii)),char(key),char(z.Subject(1)), ...
                       B.A_JND(ii)-z.JND_A(1), B.V_JND(ii)-z.JND_V(1)};
end
MatchAudit = cell2table(matchRows,'VariableNames', ...
    {'BaselineID','SubjectKey','RealFitID','DeltaJND_A','DeltaJND_V'});
MatchAudit.BaselineID = string(MatchAudit.BaselineID);
MatchAudit.SubjectKey = string(MatchAudit.SubjectKey);
MatchAudit.RealFitID  = string(MatchAudit.RealFitID);
writetable(MatchAudit,fullfile(OUT_DIR,'Figure2_SubjectMatch_Audit.csv'));

if any(abs(MatchAudit.DeltaJND_A)>1e-8 | abs(MatchAudit.DeltaJND_V)>1e-8)
    warning('At least one matched participant has a JND mismatch. Inspect Figure2_SubjectMatch_Audit.csv.');
end

% ---- Reconstruct the reliability predictors used in the completed GLMEs.
logJointPrecision = log(1 ./ (B.A_JND.^2 + B.V_JND.^2));
logRel_AoverV     = log((B.V_JND ./ B.A_JND).^2);

meanLogJoint = mean(logJointPrecision,'omitnan');
meanLogRel   = mean(logRel_AoverV,'omitnan');

logJointC = logJointPrecision - meanLogJoint;
relC      = logRel_AoverV - meanLogRel;

qJoint = prctile(logJointC,[25 75]);
qRel   = prctile(relC,[5 95]);

% Empirical disparity range implied by the programmed 7x7 grid and
% participant-specific PSE centering.
isi = 30:30:210;
allD = [];
for i = 1:height(B)
    [AA,VV] = ndgrid(isi,isi);
    d = abs((AA - B.A_PSE(i)) - (VV - B.V_PSE(i)));
    allD = [allD; d(:)]; %#ok<AGROW>
end
% Cover the full observed primary-sample disparity range so the fitted
% curve spans all descriptive empirical points. This changes visualization
% only; it does not refit the GLME.
dMax = ceil(max(allD)/30)*30;
dMax = max(180,min(330,dMax));
dms = linspace(0,dMax,121)';
D30 = dms/30;

% ---- Pull final correlated-random-slope fixed effects.
Cc = C(C.Outcome=="Causal" & C.RandomModel=="RandomSlope_Correlated",:);
Cm = C(C.Outcome=="Motion" & C.RandomModel=="RandomSlopes_Correlated",:);

bc = @(name) getBeta(Cc,name);
bm = @(name) getBeta(Cm,name);
logistic = @(x) 1./(1+exp(-x));

%% Figure 2A: Causal disparity by task at mean reliability
tasks = ["AttendV","AttendA"];
rows = {};
for it = 1:numel(tasks)
    taskA = double(tasks(it)=="AttendA");
    for j = 1:numel(D30)
        probs = nan(2,1);
        for dir2 = 0:1
            eta = bc("(Intercept)") ...
                + bc("TaskCat_AttendA")*taskA ...
                + bc("DirectionCat_2")*dir2 ...
                + bc("Dms30")*D30(j) ...
                + bc("LogJointPrecisionC")*0 ...
                + bc("LogJointPrecisionC:Dms30")*0*D30(j) ...
                + bc("TaskCat_AttendA:Dms30")*taskA*D30(j);
            probs(dir2+1) = logistic(eta);
        end
        rows(end+1,:) = {char(tasks(it)),dms(j),D30(j),mean(probs)}; %#ok<AGROW>
    end
end
T2A = cell2table(rows,'VariableNames', ...
    {'Task','Disparity_ms','Dms30','PredPCommon'});
T2A.Task = string(T2A.Task);
writetable(T2A,fullfile(OUT_DIR,'Figure2A_Causal_TaskPredictions.csv'));

%% Figure 2B: Causal disparity at low vs high empirical joint precision
rows = {};
levels = ["Lower precision","Higher precision"];
for il = 1:2
    relval = qJoint(il);
    for j = 1:numel(D30)
        probs = [];
        for taskA = 0:1
            for dir2 = 0:1
                eta = bc("(Intercept)") ...
                    + bc("TaskCat_AttendA")*taskA ...
                    + bc("DirectionCat_2")*dir2 ...
                    + bc("Dms30")*D30(j) ...
                    + bc("LogJointPrecisionC")*relval ...
                    + bc("LogJointPrecisionC:Dms30")*relval*D30(j) ...
                    + bc("TaskCat_AttendA:Dms30")*taskA*D30(j);
                probs(end+1,1) = logistic(eta); %#ok<AGROW>
            end
        end
        rows(end+1,:) = {char(levels(il)),relval,dms(j),D30(j),mean(probs)}; %#ok<AGROW>
    end
end
T2B = cell2table(rows,'VariableNames', ...
    {'PrecisionLevel','LogJointPrecisionC','Disparity_ms','Dms30','PredPCommon'});
T2B.PrecisionLevel = string(T2B.PrecisionLevel);
writetable(T2B,fullfile(OUT_DIR,'Figure2B_Causal_ReliabilityPredictions.csv'));

%% Figure 2C: reliability-dependent target/distractor influence on motion
% Work on an intuitive common x-axis:
%   baseline distractor-to-target precision ratio.
%
% AttendV: D/T = precision_A / precision_V.
% AttendA: D/T = precision_V / precision_A.
ratioAoverV = exp(logRel_AoverV);
dtRatios = [ratioAoverV; 1./ratioAoverV];
xmin = prctile(dtRatios,5);
xmax = prctile(dtRatios,95);
xDT = exp(linspace(log(xmin),log(xmax),121))';

rows = {};
for it = 1:numel(tasks)
    taskA = double(tasks(it)=="AttendA");
    for ix = 1:numel(xDT)
        % Convert common D/T ratio back into the model's A/V reliability
        % coordinate, then center using the original sample mean.
        if taskA==0       % AttendV: auditory is distractor
            logRel = log(xDT(ix));
        else              % AttendA: visual is distractor
            logRel = -log(xDT(ix));
        end
        rC = logRel - meanLogRel;

        for cue = ["Target","Distractor"]
            probs0 = nan(2,1);
            probs1 = nan(2,1);
            for dir2 = 0:1
                eta0 = bm("(Intercept)") ...
                    + bm("TaskCat_AttendA")*taskA ...
                    + bm("DirectionCat_2")*dir2 ...
                    + bm("RelBalanceC")*rC;

                target = double(cue=="Target");
                distractor = double(cue=="Distractor");

                eta1 = eta0 ...
                    + bm("Target30C")*target ...
                    + bm("Distractor30C")*distractor ...
                    + bm("TaskCat_AttendA:Target30C")*taskA*target ...
                    + bm("TaskCat_AttendA:Distractor30C")*taskA*distractor ...
                    + bm("Target30C:RelBalanceC")*target*rC ...
                    + bm("Distractor30C:RelBalanceC")*distractor*rC;

                probs0(dir2+1)=logistic(eta0);
                probs1(dir2+1)=logistic(eta1);
            end

            % Also report the corresponding log-odds slope, useful for
            % supplementary figures if desired.
            if cue=="Target"
                slope = bm("Target30C") ...
                    + bm("TaskCat_AttendA:Target30C")*taskA ...
                    + bm("Target30C:RelBalanceC")*rC;
            else
                slope = bm("Distractor30C") ...
                    + bm("TaskCat_AttendA:Distractor30C")*taskA ...
                    + bm("Distractor30C:RelBalanceC")*rC;
            end

            rows(end+1,:) = {char(tasks(it)),char(cue),xDT(ix),rC, ...
                mean(probs1-probs0),slope}; %#ok<AGROW>
        end
    end
end

T2C = cell2table(rows,'VariableNames', ...
    {'Task','Cue','DistractorTargetPrecisionRatio','RelBalanceC', ...
     'DeltaPGroup_per30ms','LogOddsSlope_per30ms'});
T2C.Task = string(T2C.Task);
T2C.Cue  = string(T2C.Cue);
writetable(T2C,fullfile(OUT_DIR,'Figure2C_Motion_ReliabilityPredictions.csv'));

%% Metadata
fid = fopen(fullfile(OUT_DIR,'Figure2_Prediction_Metadata.txt'),'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'Population-level prediction grids from saved random-slope GLME fixed effects.\n');
fprintf(fid,'No model was refit.\n\n');
fprintf(fid,'Primary N = %d\n',height(B));
fprintf(fid,'Mean log joint precision = %.8f\n',meanLogJoint);
fprintf(fid,'Mean log A/V precision ratio = %.8f\n',meanLogRel);
fprintf(fid,'Figure 2B lower/upper centered precision values = %.8f, %.8f\n',qJoint(1),qJoint(2));
fprintf(fid,'Figure 2C empirical 5th-95th distractor/target precision ratio = %.6f to %.6f\n',xmin,xmax);
fprintf(fid,'Figure 2 disparity range = 0 to %.1f ms\n',dMax);
fprintf(fid,['Causal predictions average fixed-effect probabilities over Direction 1/2.\n' ...
             'Figure 2B additionally averages over AttendV/AttendA because the Task x disparity interaction was negligible.\n' ...
             'Motion DeltaP is the predicted P(group) change for a +30-ms cue shift from the centered origin.\n']);

fprintf('\nDone. Prediction grids written to:\n%s\n',OUT_DIR);

%% ---------------- local helpers ----------------
function p = findOne(rootDir,fileName)
    d = dir(fullfile(rootDir,'**',fileName));
    if isempty(d)
        error('Could not find %s under %s',fileName,rootDir);
    end
    if numel(d)>1
        [~,ix] = max([d.datenum]);
        d = d(ix);
    end
    p = fullfile(d.folder,d.name);
end


function k = subjectKey(ids)
    ids = string(ids);
    k = strings(size(ids));
    for jj = 1:numel(ids)
        tok = regexp(char(ids(jj)),'^S\d+','match','once');
        if isempty(tok)
            error('Could not extract numeric subject key from ID: %s',ids(jj));
        end
        k(jj) = string(tok);
    end
end

function b = getBeta(T,name)
    ix = T.Name==string(name);
    if nnz(ix)~=1
        error('Expected exactly one coefficient named "%s"; found %d.',name,nnz(ix));
    end
    b = T.Estimate(ix);
end
