% List of open inputs
nrun = X; % enter the number of runs here
jobfile = {'/imaging/henson/Wakeman/pranay_does_things/4_projects/CBU_Neuroimaging_Multimodal_DCM_2024/preflight/code/fmri/saved_from_batch_interface/batch_dcm_peb_bmr_search_job.m'};
jobs = repmat(jobfile, 1, nrun);
inputs = cell(0, nrun);
for crun = 1:nrun
end
spm('defaults', 'FMRI');
spm_jobman('run', jobs, inputs{:});
