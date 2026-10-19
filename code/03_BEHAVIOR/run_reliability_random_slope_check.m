%% run_reliability_random_slope_check.m
% Robustness check for the baseline-JND reliability effects using
% participant-level random slopes.
%
% This script does NOT modify the primary BCI models.
% It tests whether the previously observed:
%   1) disparity x joint precision effect on causal judgments
%   2) distractor x relative reliability effect on motion judgments
% remain present when within-subject slopes are allowed to vary.

clear; clc; close all;

ANALYSIS_ROOT = 'C:\MSI\oscillation\ternus AV BCI\analysis0906';
PHASE2_DIR = fullfile(ANALYSIS_ROOT,'Analysis_Output_v4_R2_070');
PHASE2_MAT = fullfile(PHASE2_DIR,'Phase2_Analysis_Results_v4.mat');
OUT_DIR = fullfile(PHASE2_DIR,'Reliability_RandomSlope_Check');

if ~exist(OUT_DIR,'dir'), mkdir(OUT_DIR); end
if ~exist(PHASE2_MAT,'file'), error('Missing %s',PHASE2_MAT); end

reportPath=fullfile(OUT_DIR,'Reliability_RandomSlope_Summary.txt');
if exist(reportPath,'file'),delete(reportPath);end
diary(reportPath); diary on;
cleanupDiary=onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('============================================================\n');
fprintf(' Reliability random-slope robustness check\n');
fprintf(' Started: %s\n',datestr(now));
fprintf('============================================================\n\n');

S=load(PHASE2_MAT,'qualityTable','trialTable');
q=S.qualityTable; T=S.trialTable;
ids=string(q.ID(q.R2PrimaryIncluded));

qr=q(q.R2PrimaryIncluded,:);
R=table();
R.Subject=string(qr.ID);
R.JND_A=qr.A_JND;
R.JND_V=qr.V_JND;
R.Precision_A=1./R.JND_A.^2;
R.Precision_V=1./R.JND_V.^2;
R.LogJointPrecision=log(1./(R.JND_A.^2+R.JND_V.^2));
R.LogJointPrecisionC=R.LogJointPrecision-mean(R.LogJointPrecision,'omitnan');

modelRows=cell(0,9);
coefAll=table();

%% ================= CAUSAL =================
fprintf('[1/2] Causal judgment random-slope models...\n');

d=T(ismember(string(T.Subject),ids)&ismember(string(T.Task),["AttendV","AttendA"]),:);
d=d(isfinite(d.RespCausal)&isfinite(d.AbsPSECenteredDiff)&isfinite(d.Direction),:);
d.Subject=string(d.Subject);
d.Task=string(d.Task);
d=innerjoin(d,R(:,{'Subject','LogJointPrecisionC'}),'Keys','Subject');

d.SubjectCat=categorical(d.Subject);
d.TaskCat=categorical(d.Task,{'AttendV','AttendA'});
d.DirectionCat=categorical(d.Direction);
d.Dms30=d.AbsPSECenteredDiff/30;

causalNames=["RI","RandomSlope_Correlated","RandomSlope_Independent"];
causalFormulas={ ...
    'RespCausal ~ TaskCat + DirectionCat + Dms30 + LogJointPrecisionC + Dms30:LogJointPrecisionC + TaskCat:Dms30 + (1|SubjectCat)', ...
    'RespCausal ~ TaskCat + DirectionCat + Dms30 + LogJointPrecisionC + Dms30:LogJointPrecisionC + TaskCat:Dms30 + (1 + Dms30|SubjectCat)', ...
    'RespCausal ~ TaskCat + DirectionCat + Dms30 + LogJointPrecisionC + Dms30:LogJointPrecisionC + TaskCat:Dms30 + (1|SubjectCat) + (0 + Dms30|SubjectCat)'};

for i=1:numel(causalFormulas)
    try
        m=fitglme(d,causalFormulas{i},'Distribution','Binomial','Link','logit', ...
            'FitMethod','Laplace');
        modelRows(end+1,:)={'Causal',char(causalNames(i)),height(d),numel(unique(d.Subject)), ...
            m.ModelCriterion.AIC,m.ModelCriterion.BIC,m.LogLikelihood,causalFormulas{i},true}; %#ok<AGROW>
        c=coeffTable(m);
        c.Outcome=repmat("Causal",height(c),1);
        c.RandomModel=repmat(causalNames(i),height(c),1);
        coefAll=appendTable(coefAll,c);
        fprintf('  %-24s BIC=%.2f\n',causalNames(i),m.ModelCriterion.BIC);
    catch ME
        modelRows(end+1,:)={'Causal',char(causalNames(i)),height(d),numel(unique(d.Subject)), ...
            NaN,NaN,NaN,causalFormulas{i},false}; %#ok<AGROW>
        fprintf('  %-24s FAILED: %s\n',causalNames(i),ME.message);
    end
end

%% ================= MOTION =================
fprintf('\n[2/2] Motion judgment random-slope models...\n');

d=T(ismember(string(T.Subject),ids)&ismember(string(T.Task),["AttendV","AttendA"]),:);
d=d(isfinite(d.RespMotion)&isfinite(d.TargetCentered)&isfinite(d.DistractorCentered)&isfinite(d.Direction),:);
d.Subject=string(d.Subject);
d.Task=string(d.Task);
d=innerjoin(d,R(:,{'Subject','Precision_A','Precision_V'}),'Keys','Subject');

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
d.RelBalanceC=relBalance-mean(relBalance,'omitnan');

fixed='RespMotion ~ TaskCat + DirectionCat + Target30C + Distractor30C + TaskCat:Target30C + TaskCat:Distractor30C + RelBalanceC + Target30C:RelBalanceC + Distractor30C:RelBalanceC';
motionNames=["RI","RandomSlopes_Correlated","RandomSlopes_Independent"];
motionFormulas={ ...
    [fixed ' + (1|SubjectCat)'], ...
    [fixed ' + (1 + Target30C + Distractor30C|SubjectCat)'], ...
    [fixed ' + (1|SubjectCat) + (0 + Target30C|SubjectCat) + (0 + Distractor30C|SubjectCat)']};

for i=1:numel(motionFormulas)
    try
        m=fitglme(d,motionFormulas{i},'Distribution','Binomial','Link','logit', ...
            'FitMethod','Laplace');
        modelRows(end+1,:)={'Motion',char(motionNames(i)),height(d),numel(unique(d.Subject)), ...
            m.ModelCriterion.AIC,m.ModelCriterion.BIC,m.LogLikelihood,motionFormulas{i},true}; %#ok<AGROW>
        c=coeffTable(m);
        c.Outcome=repmat("Motion",height(c),1);
        c.RandomModel=repmat(motionNames(i),height(c),1);
        coefAll=appendTable(coefAll,c);
        fprintf('  %-24s BIC=%.2f\n',motionNames(i),m.ModelCriterion.BIC);
    catch ME
        modelRows(end+1,:)={'Motion',char(motionNames(i)),height(d),numel(unique(d.Subject)), ...
            NaN,NaN,NaN,motionFormulas{i},false}; %#ok<AGROW>
        fprintf('  %-24s FAILED: %s\n',motionNames(i),ME.message);
    end
end

modelComp=cell2table(modelRows,'VariableNames', ...
    {'Outcome','RandomModel','NTrials','NSubjects','AIC','BIC','LogLikelihood','Formula','FitOK'});
writetable(modelComp,fullfile(OUT_DIR,'Reliability_RandomSlope_ModelComparison.csv'));
writetable(coefAll,fullfile(OUT_DIR,'Reliability_RandomSlope_Coefficients.csv'));

fprintf('\nKEY COEFFICIENTS\n');
keyMask=contains(string(coefAll.Name),'Dms30:LogJointPrecisionC') | ...
        contains(string(coefAll.Name),'LogJointPrecisionC:Dms30') | ...
        contains(string(coefAll.Name),'Distractor30C:RelBalanceC') | ...
        contains(string(coefAll.Name),'RelBalanceC:Distractor30C') | ...
        contains(string(coefAll.Name),'Target30C:RelBalanceC') | ...
        contains(string(coefAll.Name),'RelBalanceC:Target30C');
disp(coefAll(keyMask,:));

fprintf('\nFinished: %s\n',datestr(now));
diary off;

%% ================= LOCAL FUNCTIONS =================

function c=coeffTable(m)
    c=m.Coefficients;
    if isa(c,'dataset'), c=dataset2table(c); end
    if ~istable(c), c=struct2table(c); end
end

function out=appendTable(out,x)
    if isempty(out), out=x; else, out=[out;x]; end %#ok<AGROW>
end
