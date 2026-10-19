%% run_JND_informed_BCI_recovery_v1.m
% JND-informed reliability model recovery.
%
% IMPORTANT:
% This script does NOT fit the new JND-informed model to the real data.
% It first asks whether independent baseline JND information improves
% model identifiability on synthetic data.
%
% Generating truth:
%   JND-ratio-informed MA / FF / Segregation.
%
% The SAME synthetic dataset is then fitted by:
%   Family 1: Standard Free-Reliability MA / FF / Seg
%   Family 2: JND-Ratio-Informed MA / FF / Seg
%
% JND-informed parameterization:
%   sigA = k * JND_A
%   sigV = k * JND_V
%
% JND is therefore NOT equated with sensory sigma. k is a free rescaling.

clear; clc; close all;

%% ================= PATHS =================
ANALYSIS_ROOT='C:\MSI\oscillation\ternus AV BCI\analysis0906';
SCRIPT_DIR=fullfile(ANALYSIS_ROOT,'analysis');
PHASE2_DIR=fullfile(ANALYSIS_ROOT,'Analysis_Output_v4_R2_070');
PHASE2_MAT=fullfile(PHASE2_DIR,'Phase2_Analysis_Results_v4.mat');
OUT_DIR=fullfile(PHASE2_DIR,'JND_Informed_Recovery_v1');

if ~exist(OUT_DIR,'dir'),mkdir(OUT_DIR);end
if ~exist(PHASE2_MAT,'file'),error('Missing %s',PHASE2_MAT);end
addpath(SCRIPT_DIR);

if exist('computeRespDistrib_AVTernus_v4','file')~=2
    error('computeRespDistrib_AVTernus_v4.m must be in the analysis folder / MATLAB path.');
end

%% ================= SETTINGS =================
MODEL_CODES=[1 4 5];
MODEL_NAMES={'ModelAveraging','ForcedFusion','Segregation'};
FREE_K=[6 5 5];
JND_K=[5 4 4];

N_SIM_GENERATE=12000;
N_SIM_FIT=2500;
N_STARTS=5;
N_COHORT_REPS=1;

% Final cache only. This is not a checkpoint/resume system.
REFIT=false;
CACHE=fullfile(OUT_DIR,'JND_Informed_Recovery_v1.mat');

reportPath=fullfile(OUT_DIR,'JND_Recovery_Summary.txt');
if exist(reportPath,'file'),delete(reportPath);end
diary(reportPath);diary on;
cleanupDiary=onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('=====================================================================\n');
fprintf(' JND-informed Ternus BCI model recovery\n');
fprintf(' Started: %s\n',datestr(now));
fprintf(' N_SIM_GENERATE=%d | N_SIM_FIT=%d | N_STARTS=%d\n', ...
    N_SIM_GENERATE,N_SIM_FIT,N_STARTS);
fprintf('=====================================================================\n\n');

%% ================= LOAD =================
S=load(PHASE2_MAT,'qualityTable','trialTable','bciFits','recoveryConfusion');
q=S.qualityTable;
T=S.trialTable;
realFits=S.bciFits;

ids=string(q.ID(q.R2PrimaryIncluded));
fprintf('Primary participants: N=%d\n',numel(ids));
fprintf('All 49 AV conditions retained.\n');
fprintf('Coordinate: PSE-centered milliseconds.\n\n');

if ~REFIT && exist(CACHE,'file')
    fprintf('Loading existing final cache:\n  %s\n\n',CACHE);
    C=load(CACHE);
    allFits=C.allFits;
    winners=C.winners;
    confusion=C.confusion;
    groupRecovery=C.groupRecovery;
    parameterRecovery=C.parameterRecovery;
    recoveryComparison=C.recoveryComparison;
    projectedTruth=C.projectedTruth;
else
    %% ================= PROJECT GENERATING PARAMETERS =================
    fprintf('[1/4] Projecting empirical free-fit parameters into JND-informed generating space...\n');
    projectedTruth=buildProjectedTruth(realFits,q,ids,MODEL_NAMES);
    writetable(projectedTruth,fullfile(OUT_DIR,'JND_Projected_Generating_Parameters.csv'));

    %% ================= RECOVERY =================
    fprintf('[2/4] Generating synthetic data and fitting both model families...\n');
    [allFits,winners,confusion,groupRecovery]=runRecovery( ...
        T,q,ids,projectedTruth,MODEL_CODES,MODEL_NAMES,FREE_K,JND_K, ...
        N_SIM_GENERATE,N_SIM_FIT,N_STARTS,N_COHORT_REPS);

    %% ================= PARAMETER RECOVERY =================
    fprintf('\n[3/4] Building parameter-recovery summaries...\n');
    parameterRecovery=buildJNDParameterRecovery(allFits,MODEL_NAMES);

    %% ================= FAMILY COMPARISON =================
    fprintf('[4/4] Comparing Free vs JND-informed recovery on identical synthetic data...\n');
    recoveryComparison=compareRecoveryFamilies(confusion,MODEL_NAMES);

    save(CACHE,'allFits','winners','confusion','groupRecovery','parameterRecovery', ...
        'recoveryComparison','projectedTruth','ids','MODEL_CODES','MODEL_NAMES', ...
        'N_SIM_GENERATE','N_SIM_FIT','N_STARTS','N_COHORT_REPS','-v7.3');
end

%% ================= SAVE TABLES =================
writetable(allFits,fullfile(OUT_DIR,'JND_Recovery_AllFits.csv'));
writetable(winners,fullfile(OUT_DIR,'JND_Recovery_Winners.csv'));
writetable(confusion,fullfile(OUT_DIR,'JND_Recovery_Confusion.csv'));
writetable(groupRecovery,fullfile(OUT_DIR,'JND_Recovery_Group.csv'));
writetable(parameterRecovery,fullfile(OUT_DIR,'JND_Parameter_Recovery.csv'));
writetable(recoveryComparison,fullfile(OUT_DIR,'JND_vs_Free_Recovery_Comparison.csv'));

fprintf('\n================ MODEL RECOVERY CONFUSION ================\n');
disp(confusion);

fprintf('\n================ SAME-DATA FAMILY COMPARISON ==============\n');
disp(recoveryComparison);

fprintf('\n================ GROUP RECOVERY ============================\n');
disp(groupRecovery);

fprintf('\n================ PARAMETER RECOVERY ========================\n');
disp(parameterRecovery);

% Also print the original free-model recovery as context, but do not use it
% as the primary same-data comparison because its generating datasets differ.
if isfield(S,'recoveryConfusion') && ~isempty(S.recoveryConfusion)
    fprintf('\n================ ORIGINAL PHASE-2 FREE RECOVERY (CONTEXT) ==\n');
    disp(S.recoveryConfusion);
end

fprintf('\n=====================================================================\n');
fprintf('Finished: %s\n',datestr(now));
fprintf('Output:\n  %s\n',OUT_DIR);
fprintf('Primary file to return:\n  %s\n',reportPath);
fprintf('=====================================================================\n');
diary off;

%% =====================================================================
% LOCAL FUNCTIONS
% ======================================================================

function truth=buildProjectedTruth(realFits,q,ids,modelNames)
    tasks=["AttendV","AttendA"];
    rows=cell(0,14);

    for it=1:numel(tasks)
        for im=1:numel(modelNames)
            m=string(modelNames{im});
            for is=1:numel(ids)
                sid=ids(is);
                qi=find(string(q.ID)==sid,1);
                if isempty(qi),continue;end
                jA=q.A_JND(qi); jV=q.V_JND(qi);
                if ~all(isfinite([jA jV])) || any([jA jV]<=0),continue;end

                rf=realFits(string(realFits.Subject)==sid & string(realFits.Task)==tasks(it) & ...
                    string(realFits.Model)==m & string(realFits.Coordinate)=="pse_centered",:);
                if height(rf)~=1,continue;end

                kA=rf.sigA/jA;
                kV=rf.sigV/jV;
                if ~all(isfinite([kA kV])) || any([kA kV]<=0),continue;end

                % Positive scale projection: geometric mean of the two
                % empirical free-model scale ratios.
                kProj=sqrt(kA*kV);
                [kLB,kUB]=kBounds(jA,jV);
                kProj=min(max(kProj,kLB+1e-6),kUB-1e-6);

                pC=rf.pCommon;
                if m=="ForcedFusion",pC=1;elseif m=="Segregation",pC=0;end

                sigA=kProj*jA;
                sigV=kProj*jV;

                rows(end+1,:)={char(sid),char(tasks(it)),char(m),jA,jV,kA,kV,kProj, ...
                    pC,rf.muP,rf.sigP,sigA,sigV,rf.Criterion}; %#ok<AGROW>
            end
        end
    end

    truth=cell2table(rows,'VariableNames',{'Subject','Task','GeneratingModel', ...
        'JND_A','JND_V','FreeScaleA','FreeScaleV','True_k', ...
        'True_pCommon','True_muP','True_sigP','True_sigA','True_sigV','True_Criterion'});
end

function [fits,winners,confusion,groupRecovery]=runRecovery( ...
    T,q,ids,truth,modelCodes,modelNames,freeK,jndK,nSimGen,nSimFit,nStarts,nReps)

    tasks=["AttendV","AttendA"];
    modelTasks=["Attend_V","Attend_A"];
    fitFamilies=["Free","JNDInformed"];

    nTotal=nReps*numel(tasks)*numel(modelCodes)*numel(ids)*numel(fitFamilies)*numel(modelCodes);
    done=0; runTic=tic;
    rows=cell(0,34);

    opts=optimset('MaxIter',1200,'MaxFunEvals',6000,'Display','off','TolFun',2e-4,'TolX',2e-4);

    for rep=1:nReps
        for it=1:numel(tasks)
            task=tasks(it);
            for ig=1:numel(modelCodes)
                genCode=modelCodes(ig);
                genName=string(modelNames{ig});

                for is=1:numel(ids)
                    sid=ids(is);
                    [info,jA,jV]=prepareConditionData(T,q,sid,task);
                    if isempty(info.counts),continue;end

                    tr=truth(string(truth.Subject)==sid & string(truth.Task)==task & ...
                        string(truth.GeneratingModel)==genName,:);
                    if height(tr)~=1,continue;end

                    truePhi=[tr.True_pCommon tr.True_muP tr.True_sigP tr.True_sigA tr.True_sigV tr.True_Criterion];
                    trueK=tr.True_k;

                    seedGen=91000000+rep*1000000+it*100000+ig*10000+is;
                    old=rng;rng(seedGen,'twister');
                    xAGen=randn(info.nCond,nSimGen);
                    xVGen=randn(info.nCond,nSimGen);
                    rng(old);

                    pGen=struct('iModel',genCode,'taskName',char(modelTasks(it)), ...
                        'sA',repmat(info.sA,1,nSimGen),'sV',repmat(info.sV,1,nSimGen), ...
                        'xAPre',xAGen,'xVPre',xVGen);
                    [pMotion,~]=computeRespDistrib_AVTernus_v4(truePhi,pGen);
                    synth=drawSyntheticCounts(info.counts,pMotion(:,2),seedGen+333);

                    seedFit=92000000+rep*1000000+it*100000+ig*10000+is;
                    old=rng;rng(seedFit,'twister');
                    xAFit=randn(info.nCond,nSimFit);
                    xVFit=randn(info.nCond,nSimFit);
                    rng(old);

                    for iff=1:numel(fitFamilies)
                        family=fitFamilies(iff);

                        for im=1:numel(modelCodes)
                            fitCode=modelCodes(im);
                            fitName=string(modelNames{im});

                            if family=="Free"
                                [phiHat,kHat,nll]=fitFree(info,synth,char(modelTasks(it)),fitCode, ...
                                    jA,jV,xAFit,xVFit,nStarts,seedFit+1000*iff+100*im,opts);
                                K=freeK(im);
                            else
                                [phiHat,kHat,nll]=fitJND(info,synth,char(modelTasks(it)),fitCode, ...
                                    jA,jV,xAFit,xVFit,nStarts,seedFit+1000*iff+100*im,opts,trueK);
                                K=jndK(im);
                            end

                            nTrials=sum(synth,'all');
                            LL=-nll;
                            AIC=2*nll+2*K;
                            BIC=2*nll+K*log(nTrials);

                            rows(end+1,:)={rep,char(sid),char(task),char(genName),char(family),char(fitName), ...
                                nTrials,info.nCond,jA,jV,trueK, ...
                                truePhi(1),truePhi(2),truePhi(3),truePhi(4),truePhi(5),truePhi(6), ...
                                kHat,phiHat(1),phiHat(2),phiHat(3),phiHat(4),phiHat(5),phiHat(6), ...
                                LL,AIC,BIC,K,nll,seedGen,seedFit,ig,im,iff}; %#ok<AGROW>

                            done=done+1;
                            elapsed=toc(runTic);
                            eta=elapsed/max(done,1)*(nTotal-done);
                            fprintf('Recovery %4d/%4d (%5.1f%%) | %s | gen %-14s | %-11s -> %-14s | elapsed %s | ETA %s\n', ...
                                done,nTotal,100*done/nTotal,char(sid),char(genName),char(family),char(fitName), ...
                                fmtTime(elapsed),fmtTime(eta));
                        end
                    end
                end
            end
        end
    end

    fits=cell2table(rows,'VariableNames',{'CohortRep','Subject','Task','GeneratingModel', ...
        'FitFamily','FittedModel','NTrials','NConditions','JND_A','JND_V','True_k', ...
        'True_pCommon','True_muP','True_sigP','True_sigA','True_sigV','True_Criterion', ...
        'Fit_k','Fit_pCommon','Fit_muP','Fit_sigP','Fit_sigA','Fit_sigV','Fit_Criterion', ...
        'LLK','AIC','BIC','K','NegLL','GenerationSeed','FitSeed','GeneratingModelIndex', ...
        'FittedModelIndex','FitFamilyIndex'});

    winners=buildWinners(fits,modelNames);
    confusion=buildConfusion(winners,modelNames);
    groupRecovery=buildGroupRecovery(fits,modelNames);
end

function [info,jA,jV]=prepareConditionData(T,q,sid,task)
    qi=find(string(q.ID)==sid,1);
    if isempty(qi),error('Missing q row for %s',sid);end
    jA=q.A_JND(qi);jV=q.V_JND(qi);

    d=T(string(T.Subject)==sid & string(T.Task)==task,:);
    d=d(isfinite(d.RespMotion)&isfinite(d.CenteredA)&isfinite(d.CenteredV)& ...
        isfinite(d.ISI_A)&isfinite(d.ISI_V),:);

    if isempty(d)
        info=struct('counts',[],'sA',[],'sV',[],'nCond',0);
        return;
    end

    nominal=[d.ISI_A,d.ISI_V];
    [~,~,g]=unique(nominal,'rows');
    nCond=max(g);
    counts=zeros(nCond,2);
    sA=zeros(nCond,1);sV=zeros(nCond,1);

    for c=1:nCond
        idx=g==c;
        counts(c,:)=[sum(d.RespMotion(idx)==0),sum(d.RespMotion(idx)==1)];
        sA(c)=mean(d.CenteredA(idx),'omitnan');
        sV(c)=mean(d.CenteredV(idx),'omitnan');
    end

    info=struct('counts',counts,'sA',sA,'sV',sV,'nCond',nCond);
end

function [phiHat,kHat,bestNLL]=fitFree(info,counts,modelTask,modelCode,jA,jV,xA,xV,nStarts,seed,opts)
    LB=[0.001,-180,1,1,1,-180];
    UB=[0.999, 180,250,250,250,180];
    start=[0.5,0,60,30,30,0];

    freeMask=true(1,6);
    fixed=nan(1,6);
    if modelCode==4
        freeMask(1)=false;fixed(1)=1;
    elseif modelCode==5
        freeMask(1)=false;fixed(1)=0;
    end

    param=struct('iModel',modelCode,'taskName',modelTask, ...
        'sA',repmat(info.sA,1,size(xA,2)),'sV',repmat(info.sV,1,size(xV,2)), ...
        'xAPre',xA,'xVPre',xV,'dataCounts',counts,'freeMask',freeMask,'fixedPhi',fixed);

    bestNLL=inf;phiHat=nan(1,6);
    old=rng;rng(seed,'twister');

    for st=1:nStarts
        if st==1
            x0=start;
        else
            x0=LB+rand(1,6).*(UB-LB);
        end
        if modelCode~=1,x0(1)=fixed(1);end

        [xh,nll]=boundedFminsearch(@(z) negLLFree(z,param), ...
            x0(freeMask),LB(freeMask),UB(freeMask),opts);

        if isfinite(nll)&&nll<bestNLL
            bestNLL=nll;
            tmp=fixed;tmp(freeMask)=xh;phiHat=tmp;
        end
    end
    rng(old);

    % Implied scale is descriptive only for the unconstrained family.
    if all(isfinite(phiHat([4 5])))
        kHat=sqrt((phiHat(4)/jA)*(phiHat(5)/jV));
    else
        kHat=NaN;
    end
end

function nll=negLLFree(z,param)
    try
        phi=param.fixedPhi;
        phi(param.freeMask)=z;
        [p,~]=computeRespDistrib_AVTernus_v4(phi,param);
        nll=binomialNLL(param.dataCounts,p(:,2));
    catch
        nll=1e12;
    end
end

function [phiHat,kHat,bestNLL]=fitJND(info,counts,modelTask,modelCode,jA,jV,xA,xV,nStarts,seed,opts,kStart)
    [kLB,kUB]=kBounds(jA,jV);

    if modelCode==1
        LB=[0.001,-180,1,kLB,-180];
        UB=[0.999, 180,250,kUB, 180];
        start=[0.5,0,60,min(max(kStart,kLB),kUB),0];
    else
        LB=[-180,1,kLB,-180];
        UB=[ 180,250,kUB,180];
        start=[0,60,min(max(kStart,kLB),kUB),0];
    end

    param=struct('iModel',modelCode,'taskName',modelTask, ...
        'sA',repmat(info.sA,1,size(xA,2)),'sV',repmat(info.sV,1,size(xV,2)), ...
        'xAPre',xA,'xVPre',xV,'dataCounts',counts,'JND_A',jA,'JND_V',jV);

    bestNLL=inf;phiHat=nan(1,6);kHat=NaN;
    old=rng;rng(seed,'twister');

    for st=1:nStarts
        if st==1
            x0=start;
        else
            x0=LB+rand(1,numel(LB)).*(UB-LB);
        end

        [xh,nll]=boundedFminsearch(@(z) negLLJND(z,param),x0,LB,UB,opts);
        if isfinite(nll)&&nll<bestNLL
            bestNLL=nll;
            [phi,k]=thetaToPhiJND(xh,param);
            phiHat=phi;kHat=k;
        end
    end
    rng(old);
end

function nll=negLLJND(theta,param)
    try
        [phi,~]=thetaToPhiJND(theta,param);
        [p,~]=computeRespDistrib_AVTernus_v4(phi,param);
        nll=binomialNLL(param.dataCounts,p(:,2));
    catch
        nll=1e12;
    end
end

function [phi,k]=thetaToPhiJND(theta,param)
    theta=double(theta(:)');
    if param.iModel==1
        if numel(theta)~=5,error('MA JND theta must have 5 params');end
        pC=theta(1);mu=theta(2);sigP=theta(3);k=theta(4);crit=theta(5);
    else
        if numel(theta)~=4,error('FF/Seg JND theta must have 4 params');end
        mu=theta(1);sigP=theta(2);k=theta(3);crit=theta(4);
        if param.iModel==4,pC=1;else,pC=0;end
    end

    sigA=k*param.JND_A;
    sigV=k*param.JND_V;
    phi=[pC,mu,sigP,sigA,sigV,crit];
end

function nll=binomialNLL(counts,pGroup)
    pGroup=min(max(double(pGroup(:)),realmin('double')),1-realmin('double'));
    counts=double(counts);
    n=sum(counts,2);k0=counts(:,1);k1=counts(:,2);
    ll=gammaln(n+1)-gammaln(k0+1)-gammaln(k1+1)+ ...
       k0.*log(1-pGroup)+k1.*log(pGroup);
    nll=-sum(ll);
    if ~isscalar(nll)||~isfinite(nll),nll=1e12;end
end

function [lb,ub]=kBounds(jA,jV)
    % Preserve the original sensory-sigma bounds [1,250] ms in both modalities.
    lb=max([1/jA,1/jV,1e-4]);
    ub=min([250/jA,250/jV,100]);
    if ~isfinite(lb)||~isfinite(ub)||ub<=lb
        error('Invalid k bounds for JND_A=%.4f JND_V=%.4f',jA,jV);
    end
end

function synth=drawSyntheticCounts(realCounts,pGroup,seed)
    old=rng;rng(seed,'twister');
    synth=zeros(size(realCounts));
    for c=1:size(realCounts,1)
        n=sum(realCounts(c,:));
        pg=min(max(pGroup(c),0),1);
        kg=sum(rand(n,1)<pg);
        synth(c,:)=[n-kg,kg];
    end
    rng(old);
end

function [xBest,fBest]=boundedFminsearch(fun,x0,lb,ub,options)
    x0=double(x0(:)');lb=double(lb(:)');ub=double(ub(:)');
    margin=max(1e-10,1e-8*(ub-lb));
    x0=min(max(x0,lb+margin),ub-margin);
    ratio=(x0-lb)./(ub-x0);
    y0=log(ratio);
    trans=@(y) lb+(ub-lb)./(1+exp(-min(max(y,-50),50)));
    [yb,fBest]=fminsearch(@(y) fun(trans(y)),y0,options);
    xBest=trans(yb);
end

function winners=buildWinners(fits,modelNames)
    reps=unique(fits.CohortRep);
    subjects=unique(string(fits.Subject),'stable');
    tasks=unique(string(fits.Task),'stable');
    gens=unique(string(fits.GeneratingModel),'stable');
    fams=unique(string(fits.FitFamily),'stable');
    rows=cell(0,11);

    for ir=1:numel(reps)
        for it=1:numel(tasks)
            for ig=1:numel(gens)
                for iff=1:numel(fams)
                    for is=1:numel(subjects)
                        x=fits(fits.CohortRep==reps(ir)&string(fits.Task)==tasks(it)& ...
                            string(fits.GeneratingModel)==gens(ig)&string(fits.FitFamily)==fams(iff)& ...
                            string(fits.Subject)==subjects(is),:);
                        if isempty(x),continue;end

                        b=nan(1,numel(modelNames));
                        for im=1:numel(modelNames)
                            j=find(string(x.FittedModel)==string(modelNames{im}),1);
                            if ~isempty(j),b(im)=x.BIC(j);end
                        end
                        if any(~isfinite(b)),continue;end
                        [bs,ord]=sort(b,'ascend');

                        rows(end+1,:)={reps(ir),char(subjects(is)),char(tasks(it)),char(gens(ig)), ...
                            char(fams(iff)),modelNames{ord(1)},b(1),b(2),b(3),bs(2)-bs(1), ...
                            gens(ig)==string(modelNames{ord(1)})}; %#ok<AGROW>
                    end
                end
            end
        end
    end

    winners=cell2table(rows,'VariableNames',{'CohortRep','Subject','Task','GeneratingModel', ...
        'FitFamily','WinningModel','BIC_ModelAveraging','BIC_ForcedFusion','BIC_Segregation', ...
        'DeltaBIC_SecondMinusBest','CorrectRecovery'});
end

function confusion=buildConfusion(winners,modelNames)
    tasks=unique(string(winners.Task),'stable');
    fams=unique(string(winners.FitFamily),'stable');
    rows=cell(0,8);

    for iff=1:numel(fams)
        for it=1:numel(tasks)
            for ig=1:numel(modelNames)
                mask=string(winners.FitFamily)==fams(iff)&string(winners.Task)==tasks(it)& ...
                    string(winners.GeneratingModel)==string(modelNames{ig});
                n=sum(mask);
                for iw=1:numel(modelNames)
                    k=sum(mask&string(winners.WinningModel)==string(modelNames{iw}));
                    rows(end+1,:)={char(fams(iff)),char(tasks(it)),modelNames{ig},modelNames{iw}, ...
                        n,k,k/max(n,1),ig==iw}; %#ok<AGROW>
                end
            end
        end
    end

    confusion=cell2table(rows,'VariableNames',{'FitFamily','Task','GeneratingModel','RecoveredAs', ...
        'NGenerated','NRecovered','Proportion','Diagonal'});
end

function out=buildGroupRecovery(fits,modelNames)
    reps=unique(fits.CohortRep);
    tasks=unique(string(fits.Task),'stable');
    gens=unique(string(fits.GeneratingModel),'stable');
    fams=unique(string(fits.FitFamily),'stable');
    rows=cell(0,10);

    for iff=1:numel(fams)
        for ir=1:numel(reps)
            for it=1:numel(tasks)
                for ig=1:numel(gens)
                    b=nan(1,numel(modelNames));nSub=0;
                    for im=1:numel(modelNames)
                        x=fits(string(fits.FitFamily)==fams(iff)&fits.CohortRep==reps(ir)& ...
                            string(fits.Task)==tasks(it)&string(fits.GeneratingModel)==gens(ig)& ...
                            string(fits.FittedModel)==string(modelNames{im}),:);
                        b(im)=sum(x.BIC,'omitnan');
                        nSub=max(nSub,height(x));
                    end
                    [~,ord]=sort(b,'ascend');
                    rows(end+1,:)={char(fams(iff)),reps(ir),char(tasks(it)),char(gens(ig)),nSub, ...
                        b(1),b(2),b(3),modelNames{ord(1)},gens(ig)==string(modelNames{ord(1)})}; %#ok<AGROW>
                end
            end
        end
    end

    out=cell2table(rows,'VariableNames',{'FitFamily','CohortRep','Task','GeneratingModel', ...
        'NSubjects','SumBIC_ModelAveraging','SumBIC_ForcedFusion','SumBIC_Segregation', ...
        'GroupWinner','CorrectGroupRecovery'});
end

function out=compareRecoveryFamilies(confusion,modelNames)
    tasks=unique(string(confusion.Task),'stable');
    rows=cell(0,7);

    for it=1:numel(tasks)
        for im=1:numel(modelNames)
            gen=string(modelNames{im});
            f=confusion(string(confusion.FitFamily)=="Free"&string(confusion.Task)==tasks(it)& ...
                string(confusion.GeneratingModel)==gen&string(confusion.RecoveredAs)==gen,:);
            j=confusion(string(confusion.FitFamily)=="JNDInformed"&string(confusion.Task)==tasks(it)& ...
                string(confusion.GeneratingModel)==gen&string(confusion.RecoveredAs)==gen,:);
            if isempty(f)||isempty(j),continue;end
            rows(end+1,:)={char(tasks(it)),char(gen),f.NGenerated(1), ...
                f.Proportion(1),j.Proportion(1),j.Proportion(1)-f.Proportion(1), ...
                sign(j.Proportion(1)-f.Proportion(1))}; %#ok<AGROW>
        end
    end

    out=cell2table(rows,'VariableNames',{'Task','GeneratingModel','NGenerated', ...
        'Recovery_FreeFamily','Recovery_JNDInformedFamily','Delta_JNDminusFree','Direction'});
end

function out=buildJNDParameterRecovery(fits,modelNames)
    fams=unique(string(fits.FitFamily),'stable');
    tasks=unique(string(fits.Task),'stable');
    params={'pCommon','muP','sigP','k','sigA','sigV','Criterion'};
    rows=cell(0,18);

    for iff=1:numel(fams)
        for it=1:numel(tasks)
            for im=1:numel(modelNames)
                m=string(modelNames{im});
                x=fits(string(fits.FitFamily)==fams(iff)&string(fits.Task)==tasks(it)& ...
                    string(fits.GeneratingModel)==m&string(fits.FittedModel)==m,:);
                if isempty(x),continue;end

                for ip=1:numel(params)
                    p=params{ip};
                    if strcmp(p,'pCommon')&&m~="ModelAveraging",continue;end

                    if strcmp(p,'k')
                        t=x.True_k;r=x.Fit_k;
                    else
                        t=x.(['True_' p]);r=x.(['Fit_' p]);
                    end

                    valid=isfinite(t)&isfinite(r);
                    t=t(valid);r=r(valid);
                    if numel(t)<3,continue;end

                    bias=mean(r-t);
                    rmse=sqrt(mean((r-t).^2));
                    mae=mean(abs(r-t));
                    pr=NaN;pp=NaN;sr=NaN;sp=NaN;slope=NaN;intercept=NaN;

                    if std(t)>eps&&std(r)>eps
                        try,[pr,pp]=corr(t,r,'Type','Pearson');catch,end
                        try,[sr,sp]=corr(t,r,'Type','Spearman');catch,end
                        try
                            lm=fitlm(t,r);
                            intercept=lm.Coefficients.Estimate(1);
                            slope=lm.Coefficients.Estimate(2);
                        catch
                        end
                    end

                    rows(end+1,:)={char(fams(iff)),char(tasks(it)),char(m),p,numel(t), ...
                        mean(t),std(t),mean(r),std(r),bias,rmse,mae,pr,pp,sr,sp,slope,intercept}; %#ok<AGROW>
                end
            end
        end
    end

    out=cell2table(rows,'VariableNames',{'FitFamily','Task','Model','Parameter','N', ...
        'TrueMean','TrueSD','RecoveredMean','RecoveredSD','Bias','RMSE','MAE', ...
        'PearsonR','PearsonP','SpearmanRho','SpearmanP','RecoverySlope','RecoveryIntercept'});
end

function s=fmtTime(sec)
    if ~isfinite(sec),s='--:--:--';return;end
    sec=round(sec);
    h=floor(sec/3600);
    m=floor(mod(sec,3600)/60);
    ss=mod(sec,60);
    s=sprintf('%02d:%02d:%02d',h,m,ss);
end
