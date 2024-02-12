%---------------------------------------------------------------------------------------
% Group Dynamic Causal Modelling of the Face Perception Network using MEG
%---------------------------------------------------------------------------------------
% This script consists of SPM and MATLAB code for fitting Dynamic Causal Models on MEG
% evoked responses. All analyses covered were presented as a tutorial in
% February 2024 at the MRC Cognition and Brain Sciences Unit. The script covers
% specification of a single DCM, replication of this specified DCM to multiple subjects
% (called a GCM) and fitting this 'group' DCM in parallel. Further, various ways to
% perform inference at the group level using a hierarchical Bayesian framework called
% Parametric Empirical Bayes (PEB) are also demonstrated. These include greedy search of
% nested models, binary model comparison of nested models, and comparing families of
% nested models. Lastly, the inclusion of subject-level covariates for inference at the
% group level are also demo'ed in brief.

% Note that this script directly calls relevant SPM functions for executing tasks, and
% does not rely on the batch system exposed by SPM/MATLAB.

% Sections in this script are organized in the same order as covered in the tutorial.

% Authored in September 2022 by:
%   Pranay Yadav - pranay.yadav@mrc-cbu.cam.ac.uk
% With help from:
%   Rik Henson - rik.henson@mrc-cbu.cam.ac.uk

%---------------------------------------------------------------------------------------
% Data Sources
%---------------------------------------------------------------------------------------

% A. Processed DCM-ready data can be obtained from:
%   Yadav, Pranay; Henson, Rik (2024). Dynamic Causal Modelling of Face Processing with
%   fMRI and M/EEG. figshare. Dataset. https://doi.org/10.6084/m9.figshare.25192793.v1

% B. Alternatively, raw data can be obtained from:
%   Wakeman, D.G. & Henson, R.N. (2015). A multi-subject, multi-modal human neuroimaging
%   dataset. Sci. Data 2:150001 https://doi.org/10.1038/sdata.2015.1
% Process this data as per the tutorial instructed in:
%   Henson RN, Abdulrahman H, Flandin G and Litvak V (2019) Multimodal Integration of
%   M/EEG and f/MRI Data in SPM12. Front. Neurosci. 13:300.
%   https://doi.org/10.3389/fnins.2019.00300
% Notable deviations from the script in the processing of data used in this tutorial:
%   1. Baseline correction is done during epoching for this tutorial, skipped in paper.
%   2. Robust averaging is done per condition for this tutorial (simple avg in paper).

%% -------------------------------------------------------------------------------------
%                                                            
%      .d8888b.           888                      
%     d88P  Y88b          888                      
%     Y88b.               888                      
%      "Y888b.    .d88b.  888888 888  888 88888b.  
%         "Y88b. d8P  Y8b 888    888  888 888 "88b 
%           "888 88888888 888    888  888 888  888 
%     Y88b  d88P Y8b.     Y88b.  Y88b 888 888 d88P 
%      "Y8888P"   "Y8888   "Y888  "Y88888 88888P"  
%                                         888      
%                                         888      
%                                         888                                               
%                                                                        
%---------------------------------------------------------------------------------------
% Set up the MATLAB & SPM environment with necessary paths and variables

%---------------------------------------------------------------------------------------
% STEP 1 
%---------------------------------------------------------------------------------------
clear

% Add SPM12 to MATLAB Path
SPM12PATH = '/imaging/local/software/spm_cbu_svn/releases/spm12_latest/';
addpath(SPM12PATH)

%---------------------------------------------------------------------------------------
% STEP 2: Configure & launch SPM  
%---------------------------------------------------------------------------------------

% Initialize SPM
spm('asciiwelcome');
spm_jobman('initcfg'); % Allows batch operations inside a script
spm_get_defaults('cmdline',true);
spm('defaults','EEG');

%spm eeg

%---------------------------------------------------------------------------------------
% STEP 3: Variables for folders 
%---------------------------------------------------------------------------------------

% Specify root working directory 
base_dir = '/imaging/henson/Wakeman/pranay_does_things/4_projects/CBU_Neuroimaging_Multimodal_DCM_2024/sessionlive'; % Change this to yours
addpath(genpath(fullfile(base_dir, 'code'))) % Add scripts & functions to workspace

% All fits go in this directory
fits_dir = fullfile(base_dir, 'fits', 'direct_script', 'meg');

% All code is present in this directory
code_dir = fullfile(base_dir, 'code', 'meg');

%% -------------------------------------------------------------------------------------
%                                                 
%     8888888b.   .d8888b.  888b     d888 
%     888  "Y88b d88P  Y88b 8888b   d8888 
%     888    888 888    888 88888b.d88888 
%     888    888 888        888Y88888P888 
%     888    888 888        888 Y888P 888 
%     888    888 888    888 888  Y8P  888 
%     888  .d88P Y88b  d88P 888   "   888 
%     8888888P"   "Y8888P"  888       888
%
%---------------------------------------------------------------------------------------
% Configure DCM model with data and options

% Name of this DCM model (Used for each subject's fits, and downstream by GCM/PEB)
name = 'DCM_Full';
DCM.name = name;

%---------------------------------------------------------------------------------------
% STEP 1: Setup analysis options
%---------------------------------------------------------------------------------------

% Specify modality
DCM.xY.modality = 'MEG';

% Set up DCM analysis type
DCM.options.analysis = 'ERP';   % Analyze evoked responses
DCM.options.model    = 'ERP';   % Neuronal temporal model: Extended Jansen-Rit model
DCM.options.spatial  = 'ECD';   % Spatial observation model: IMG (IMG or ECD)

% Set up preprocessing parameters and analysis options
DCM.options.Nmodes   = 8;       % Number of modes of Leadfield for data selection
DCM.options.CVA      = 0;       % Optimize modes of Leadfield
DCM.options.h        = 1;       % Number of DCT components for detrending (1 is mean)
DCM.options.han      = 1;       % Hanning Window Taper
DCM.options.onset    = 64;      % Selection of onset (prior mean) for input stimulus
DCM.options.dur      = 16;      % Duration of onset (prior sd) for input stimulus
DCM.options.D        = 1;       % Downsampling (decimation of time series by a factor)
DCM.options.multiC   = 0;       % Multiple input vectors for multiple stimuli
DCM.options.location = 0;       % Optimize dipole locations
DCM.options.symmetry = 1;       % Lock orientation of dipoles across hemispheres
DCM.options.Nmax     = 512;     % Set more fitting steps, so that all subjects converge

% Options specific to IMG spatial observation model: Hardcoded in spm_dcm_erp_dipfit.m
% DCM.M.dipfit.rad     = 10;    % Radius of sphere centered at each source ROI
% DCM.M.dipfit.Nm      = 2;     % Two modes across vertices within each source ROI

%---------------------------------------------------------------------------------------
% STEP 2: Setup data & design
%---------------------------------------------------------------------------------------

% Specify data of interest
DCM.options.trials   = [1 2]; % Index of ERPs within ERP/ERF file
DCM.options.Tdcm     = [0 400]; % Peri-stimulus time to be modelled

% Specify between-condition trial effects
contrasts = [-1 1]'; % Face Perception: Scrambled vs Faces (Famous + Unfamiliar)
DCM.xU.X = contrasts; % Orientation is N_trials x N_contrasts
DCM.xU.name = {'Face Perception'};

%--------------------------------------------------------------------------
% STEP 3: Setup observation model
%--------------------------------------------------------------------------

% Location priors for dipoles
locs  = {
    [  0, -90,   0], 'bEVC';     
    [-42, -56, -20], 'lFFA';
    [+42, -52, -14], 'rFFA';   
};

DCM.Lpos  = cat(1, locs{:,1})';
DCM.Sname = locs(:,2)';
Nareas    = length(locs);

%--------------------------------------------------------------------------
% STEP 4: Setup neuronal model
%--------------------------------------------------------------------------

% A Matrix: Forward connections
DCM.A{1} = [
%     bVC lFFA rFFA
    [  0    0    0  ];   % bVC
    [  1    0    0  ];   % lFFA
    [  1    0    0  ];   % rFFA    
];

% A Matrix: Backward connections
DCM.A{2} = [
%     bVC lFFA rFFA
    [  0    1    1  ];   % bVC
    [  0    0    0  ];   % lFFA
    [  0    0    0  ];   % rFFA    
];

% A Matrix: Lateral connections
DCM.A{3} = [
%     bVC lFFA rFFA
    [  0    0    0  ];   % bVC
    [  0    0    1  ];   % lFFA
    [  0    1    0  ];   % rFFA    
];

% B Matrix: Modulation of connections
self_connections = eye(Nareas);
DCM.B{1} = double(DCM.A{1} | DCM.A{2} | DCM.A{3} | self_connections); % Forward + Backward + Lateral + Self

% C Matrix: Driving inputs
DCM.C = [1 0 0]';

% Save full model as a template
dcm_full_file = fullfile(fits_dir, 'templates', 'DCMs', strcat(DCM.name, '.mat'));
save(dcm_full_file, 'DCM')
DCM_Full = DCM; % Keep DCM in memory

%--------------------------------------------------------------------------
% STEP 5: Specify reduced models, if any
%--------------------------------------------------------------------------

% Reduced model with modulation of only self connections
DCM.name = 'DCM_Self';
DCM.B{1} = self_connections;

% Save reduced model as a template
dcm_self_file = fullfile(fits_dir, 'templates', 'DCMs', strcat(DCM.name, '.mat'));
save(dcm_self_file, 'DCM')
DCM_Self = DCM; % Keep DCM in memory

%---------------------------------------------------------------------------------------
% STEP 6: Replicate DCM specification across subjects
%---------------------------------------------------------------------------------------

% Populate list of processed files as a column-order cell (N-files × 1)
% These files should contain forward models (with or without gain matrices)
files = dir(fullfile(base_dir, 'data', 'derivatives', '**', 'wmaM*.mat'));
input_files = arrayfun(@(x) fullfile(x.folder, x.name), files, 'UniformOutput', false);

% Generate GCM with rows corresponding to DCMs for all subjects, columns representing
% models per subject (we only have one column here for the full model)
GCM = {};
for f=1:length(input_files)    
    GCM{f, 1} = DCM_Full; % Full model
    GCM{f, 1}.xY.Dfile = input_files{f}; % Add path to subject f's data file
    GCM{f, 1}.name = sprintf('%s_sub-%02d', name, f); % Add subject identifier
end   

% Save GCM specification
save(fullfile(fits_dir, 'templates', 'GCMs', 'Full', 'GCM_DCM_Full.mat'), 'GCM')

%% -------------------------------------------------------------------------------------
%                                                                                         
%     8888888888         888    d8b                        888            
%     888                888    Y8P                        888            
%     888                888                               888            
%     8888888   .d8888b  888888 888 88888b.d88b.   8888b.  888888 .d88b.  
%     888       88K      888    888 888 "888 "88b     "88b 888   d8P  Y8b 
%     888       "Y8888b. 888    888 888  888  888 .d888888 888   88888888 
%     888            X88 Y88b.  888 888  888  888 888  888 Y88b. Y8b.     
%     8888888888 88888P'  "Y888 888 888  888  888 "Y888888  "Y888 "Y8888
%
%---------------------------------------------------------------------------------------
% Estimate specified DCMs for all subjects using direct function calls

%---------------------------------------------------------------------------------------
% STEP 1: Manage environment
%---------------------------------------------------------------------------------------

% Initialize Parallel Compute Pool (Example Instructions for CBU Cluster)
P = gcp('nocreate');
n_workers = length(input_files);
if isempty(P)
    P=cbupool(n_workers, '--mem-per-cpu=4G --time=12:00:00 --nodelist=node-j10');
    parpool(P, P.NumWorkers);
    % parpool(n_workers); % Run this line if not at the CBU
else
    disp('Pool running')
    %delete(P) % Shut down any existing pool
end

% During fitting, individual subject-level DCMs will be estimated in the working folder
% We'll navigate to the templates GCMs folder to be consistent with the 'batch' script
cd(fullfile(fits_dir, 'templates', 'GCMs', 'Full'))

%---------------------------------------------------------------------------------------
% STEP 2: Fit DCMs in parallel
%---------------------------------------------------------------------------------------

% Fit GCM
GCM = spm_dcm_fit(GCM(:, 1), true);

% Switch back to base directory
cd(base_dir)

% Save fitted GCM
save(fullfile(fits_dir, 'GCM_Full'), 'GCM')

%---------------------------------------------------------------------------------------
% STEP 3: Estimate 2nd-level PEB model
%---------------------------------------------------------------------------------------
M = []; M.Q = 'all'; % Random effects over all parameters
PEB = spm_dcm_peb(GCM, M, {'B'});

% Save estimated PEB
save(fullfile(fits_dir, 'PEB_Full'), 'PEB')

%---------------------------------------------------------------------------------------
% STEP 4: Review estimated PEB
%---------------------------------------------------------------------------------------
spm_dcm_peb_review(PEB, GCM)

%---------------------------------------------------------------------------------------
% OUTPUTS
%---------------------------------------------------------------------------------------
% Running this section will produce the following outputs in the folder 'fits_dir'
% 1. GCM specification file called 'GCM_DCM_Full.mat' under fits_dir/templates/GCMs/Full
%       This is the GCM array with full DCM models which has not yet been fitted
%       (From last, step 6 of the previous section)
% 2. Estimated GCM file called 'GCM_Full.mat' under fits_dir
%       This is the GCM array consisting of fitted DCM models, one row per subject
% 3. Estimated PEB file called 'PEB_Full.mat' under fits_dir
%       This is the group PEB estimate from the last step in the batch pipeline
% 4. Additionally, individual DCM fits are also stored in fits_dir/templates/GCMs/Full
%       These are the same as the estimated GCM file in (2) but are one per subject (16
%       total) instead of an array like GCM. Useful for quick inspection in the DCM GUI. 

%% -------------------------------------------------------------------------------------
%
%      .d8888b.                                    888      
%     d88P  Y88b                                   888      
%     Y88b.                                        888      
%      "Y888b.    .d88b.   8888b.  888d888 .d8888b 88888b.  
%         "Y88b. d8P  Y8b     "88b 888P"  d88P"    888 "88b 
%           "888 88888888 .d888888 888    888      888  888 
%     Y88b  d88P Y8b.     888  888 888    Y88b.    888  888 
%      "Y8888P"   "Y8888  "Y888888 888     "Y8888P 888  888
%
%---------------------------------------------------------------------------------------
% Perform greedy search over full model space (B-matrix) with Bayesian model reduction

%---------------------------------------------------------------------------------------
% STEP 1: Bayesian Model Selection
%---------------------------------------------------------------------------------------
[BMA, BMR] = spm_dcm_peb_bmc(PEB);

% Write to disk
save(fullfile(fits_dir, 'BMA_search_PEB_Full'), 'BMA')

%---------------------------------------------------------------------------------------
% STEP 2: Review estimated BMA
%---------------------------------------------------------------------------------------
spm_dcm_peb_review(BMA, GCM)

%---------------------------------------------------------------------------------------
% OUTPUTS
%---------------------------------------------------------------------------------------
% Running this section will produce the following output in the folder 'fits_dir'
% 1. BMA file called 'BMA_search_PEB_Full.mat' under fits_dir
%       This is the BMA obtained after averaging reduced models that contribute
%       significantly to model evidence.

%% -------------------------------------------------------------------------------------
%
%     8888888888                     d8b 888 d8b                   
%     888                            Y8P 888 Y8P                   
%     888                                888                       
%     8888888  8888b.  88888b.d88b.  888 888 888  .d88b.  .d8888b  
%     888         "88b 888 "888 "88b 888 888 888 d8P  Y8b 88K      
%     888     .d888888 888  888  888 888 888 888 88888888 "Y8888b. 
%     888     888  888 888  888  888 888 888 888 Y8b.          X88 
%     888     "Y888888 888  888  888 888 888 888  "Y8888   88888P'
%
%---------------------------------------------------------------------------------------

%---------------------------------------------------------------------------------------
% STEP 1: Define model space
%---------------------------------------------------------------------------------------

% Remove priors if present, they interfere with the internal model comparison code
if isfield(DCM_Full, 'M')
    DCM_Full = rmfield(DCM_Full, 'M');
end

% Generate all 16 models in one shot (alternatively, can use nested for-loops)
family = full(spm_perm_mtx(4));     % This has 16 rows and 4 columns
% Each column corresponds to one kind of connection, either F/B/L/S
% Assign indices to each kind of connection
i_f = 1;    i_b = 2;    i_l = 3;    i_s = 4; 

% Initialise model space, and loop over each model and turn on/off connections
n_models = size(family, 1);  % As many models as there are rows, here, 16
GCM = cell(1, n_models);
for n=1:n_models
    
    % Switches for current model, vector of 4 elements
    sw = family(n, :);
    % Separate the switches out for each kind of connection using indices defined above
    f = sw(i_f);    b = sw(i_b);    l = sw(i_l);    s = sw(i_s);
    
    % Clone the template 'Full' model and set switches on the 'b' matrix
    DCM = DCM_Full;               
    DCM.B{1}(:,:) = [
        % bEVC lFFA rFFA
        [  s    b    b ];   % bEVC
        [  f    s    l ];   % lFFA
        [  f    l    s ];   % rFFA
        ];
    
    % Store model in array
    GCM{1, n} = DCM; 
end

% Save model space
gcm_families_file = fullfile(fits_dir, 'templates', 'GCMs', 'Families', 'GCM_ModelSpace16.mat');
save(gcm_families_file, 'GCM')

% Visualize model space
figure;
for k=1:n_models
    subplot(4,4,k);
    imagesc(GCM{1, k}.B{1}(:,:) + 0.5*GCM{1, 1}.B{1}(:,:));
    xticklabels(DCM_Full.Sname);
    yticklabels(DCM_Full.Sname);
    colormap(gray)
    caxis([0, 1])
    title(sprintf('Model %02d', k))
    axis square
end

%---------------------------------------------------------------------------------------
% STEP 2: Load estimated PEB and perform BMR of model space
%---------------------------------------------------------------------------------------

% Load estimated PEB from file
load(fullfile(fits_dir, 'PEB_Full.mat'))

% Bayesian Model Reduction (BMR) and comparison of models
[BMA, BMR] = spm_dcm_peb_bmc(PEB, GCM);

% Save BMA and BMR
outfile = fullfile(fits_dir, 'BMA_BMR_Families.mat');
save(outfile, 'BMA', 'BMR')

%---------------------------------------------------------------------------------------
% STEP 3: Group models into families and compare
%---------------------------------------------------------------------------------------
% Now partition the model space into families and perform comparisons at the level of
% families to test hypotheses about modulation of connection groups due to faces

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% HYPOTHESIS 1
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% Are any between-region connections modulated regardless of self-connections?
% Family 1: Models 1 to 14 have at least one forward, backward or lateral connection
% Family 2: Models 15 and 16 have no forward, backward or lateral connections
families = family(:, i_f) | family(:, i_b) | family(:, i_l);  % Using switches
families = 1 + ~(families)'; % Family 1 with between-region; Family 2 without
% Alternatively, instead of using switches, families can be manually specified:
% families = [ones([1, 14]), 2, 2];  % Manual specification
[BMAf, fam] = spm_dcm_peb_bmc_fam(BMA, BMR, families, 'NONE');
fprintf('Evidence for family 1 (extrinsic): \t%.01f%%\n', round(100*fam.family.post(1),1));
% Family 1 has overwhelming evidence (~1) -> between-region connections are modulated

% Save this family-wise comparison
outfile = fullfile(fits_dir, 'BMC_Families_BetweenRegion.mat');
save(outfile, 'BMAf', 'fam')

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% HYPOTHESIS 2a
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% Are any forward connections modulated regardless of backward/lateral/self-connections?
% Family 1: Models 1 to 8 have at least one forward connection
% Family 2: Models 9 to 16 have no forward connection
families = family(:, i_f);   % Using switches
families = 1 + ~families'; % Family 1 with Forward; Family 2 without
% Alternatively, instead of using switches, families can be manually specified:
% families = [ones([1, 8]), 2*ones([1, 8])];  % Manual specification
[BMAf, fam] = spm_dcm_peb_bmc_fam(BMA, BMR, families, 'NONE');
fprintf('Evidence for family 1 (forward): \t%.01f%%\n', round(100*fam.family.post(1),1));
% Family 1 has overwhelming evidence (~1)

% Save this family-wise comparison
outfile = fullfile(fits_dir, 'BMC_Families_BetweenRegion_Forward.mat');
save(outfile, 'BMAf', 'fam')

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% HYPOTHESIS 2b
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% Are any backward connections modulated regardless of forward/lateral/self-connections?
% Family 1: Models 1-4 and 9-12 have at least one backward connection
% Family 2: Models 5-8 and 13-16 have no backward connection
families = family(:, i_b);
families = 1 + ~families'; % Family 1 with Backward; Family 2 without
% Alternatively, instead of using switches, families can be manually specified:
% families = repelem([1,2,1,2], 4);  % Manual specification
[BMAf, fam] = spm_dcm_peb_bmc_fam(BMA, BMR, families, 'NONE');
fprintf('Evidence for family 1 (backward): \t%.01f%%\n', round(100*fam.family.post(1),1));
% Family 1 has negligible evidence (~0.07)

% Save this family-wise comparison
outfile = fullfile(fits_dir, 'BMC_Families_BetweenRegion_Backward.mat');
save(outfile, 'BMAf', 'fam')

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% HYPOTHESIS 2c
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% Are any lateral connections modulated regardless of forward/backward/self-connections?
% Family 1: Models 1, 2, 5, 6, 9, 10, 13, 14 have at least one lateral connection
% Family 2: Models 3, 4, 7, 8, 11, 12, 15, 16 have no lateral connection
families = family(:, i_l);
families = 1 + ~families'; % Family 1 with Lateral; Family 2 without
% Alternatively, instead of using switches, families can be manually specified:
% families = repmat([1,1,2,2], [1,4]);  % Manual specification
[BMAf, fam] = spm_dcm_peb_bmc_fam(BMA, BMR, families, 'NONE');
fprintf('Evidence for family 1 (lateral): \t%.01f%%\n', round(100*fam.family.post(1),1));
% Family 1 has overwhelming evidence (~1)

% Save this family-wise comparison
outfile = fullfile(fits_dir, 'BMC_Families_BetweenRegion_Lateral.mat');
save(outfile, 'BMAf', 'fam')

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% HYPOTHESIS 3
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
% Are any self connections modulated regardless of forward/backward/lateral connections?
% Family 1: Models 1, 3, 5, 7, 9, 11, 13, 15 have at least one self connection
% Family 2: Models 2, 4, 6, 8, 10, 12, 14, 16 have no self connection
families = family(:, i_s);
families = 1 + ~families'; % Family 1 with Self; Family 2 without
% Alternatively, instead of using switches, families can be manually specified:
% families = repmat([1,2], [1,8]);  % Manual specification
[BMAf, fam] = spm_dcm_peb_bmc_fam(BMA, BMR, families, 'NONE'); 
fprintf('Evidence for family 1 (self): \t\t%.01f%%\n', round(100*fam.family.post(1),1));
% Family 1 has moderate evidence (~0.82)

% Save this family-wise comparison
outfile = fullfile(fits_dir, 'BMC_Families_Self.mat');
save(outfile, 'BMAf', 'fam')

%---------------------------------------------------------------------------------------
% OUTPUTS
%---------------------------------------------------------------------------------------
% Running this batch job will produce the following output in the folder 'fits_dir'
% 1. GCM model space file 'GCM_ModelSpace16.mat' in fits_dir/templates/GCMs/Families
%       This file consists of the 16 models we specified as columns of the GCM cell array
% 2. BMA and BMR in the file 'BMA_BMR_Families.mat' in fits_dir
%       This file consists of both BMA and BMR variables which represent the average
%       over all 8 models and the 8 reduced models respectively.
% 3. Four files in fits_dir, one for each hypothesis and family-wise comparison:
%       i. 'BMC_Families_BetweenRegion.mat': Modulation of any between-region connections
%       ii. 'BMC_Families_BetweenRegion_Forward.mat': Modulation of any forward connections
%       iii. 'BMC_Families_BetweenRegion_Backward.mat': Modulation of any backward connections
%       iv. 'BMC_Families_BetweenRegion_Lateral.mat': Modulation of any lateral connections
%       v. 'BMC_Families_Self.mat': Modulation of any self-connections

%% -------------------------------------------------------------------------------------
%
%      .d8888b.                                     d8b          888                     
%     d88P  Y88b                                    Y8P          888                     
%     888    888                                                 888                     
%     888         .d88b.  888  888  8888b.  888d888 888  8888b.  888888 .d88b.  .d8888b  
%     888        d88""88b 888  888     "88b 888P"   888     "88b 888   d8P  Y8b 88K      
%     888    888 888  888 Y88  88P .d888888 888     888 .d888888 888   88888888 "Y8888b. 
%     Y88b  d88P Y88..88P  Y8bd8P  888  888 888     888 888  888 Y88b. Y8b.          X88 
%      "Y8888P"   "Y88P"    Y88P   "Y888888 888     888 "Y888888  "Y888 "Y8888   88888P'
%
%---------------------------------------------------------------------------------------
% We demonstrate the inclusion of covariates for 2nd-level (group) inference with PEB.
% The dataset includes ages of participants, and while we do not anticipate any effect
% of age on modulation of connections due to faces, we illustrate specification of age
% as a covariate in the PEB design matrix for inference.

%---------------------------------------------------------------------------------------
% STEP 1: Setup Design Matrix with Covariates
%---------------------------------------------------------------------------------------

% Define covariates, and assign appropriate labels
covariate_name = 'Age';
covariate_values = [31, 25, 30, 26, 23, 26, 31, 26, 29, 23, 24, 24, 25, 24, 30, 25]';

% Mean-center the covariate (Optional)
covariate_values = detrend(covariate_values, 0);

% Design Matrix
M.X = [ones([length(input_files), 1]), covariate_values]; % First covariate is group mean
M.Xnames = {'Commonalities', 'Age'};
M.Q = 'all'; % Random effects over all parameters

% Load fitted GCM
load(fullfile(fits_dir, 'GCM_Full'))

%---------------------------------------------------------------------------------------
% STEP 2: Fit 2nd-level PEB
%---------------------------------------------------------------------------------------
PEB = spm_dcm_peb(GCM, M, {'B'});

% Write to disk
save(fullfile(fits_dir, 'PEB_Age'), 'PEB')

%---------------------------------------------------------------------------------------
% STEP 3: Review
%---------------------------------------------------------------------------------------
spm_dcm_peb_review(PEB, GCM)

% Greedy search for nested models on this PEB can be done to perform inference and
% identify which connections modulated by faces are affected by age.

%---------------------------------------------------------------------------------------
% OUTPUTS
%---------------------------------------------------------------------------------------
% Running this batch job will produce the following outputs in the folder 'fits_dir'
% 1. Estimated PEB file called 'PEB_Age.mat' under fits_dir
%       This is the group PEB estimated with age as a covariate.
