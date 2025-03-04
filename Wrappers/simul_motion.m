function [fitpars,RMS_displacement,RMS_rot ] = simul_motion(...
    fin, fout,noiseBasePars,maxDisp,maxRot,...
    swallowFrequency,swallowMagnitude,suddenFrequency,suddenMagnitude,seed_num)


%path to the toolbox if needed
retroMoCoPath = which('addRetroMoCoBoxToPath.m');
if isempty(retroMoCoPath)
    addpath('/network/lustre/iss01/cenir/software/irm/matlab_toolbox/retroMoCoBox')
    run('addRetroMoCoBoxToPath.m')
    % The NUFFT uses the Michigan Image Reconstruction Toolbox (MIRT)
    % (http://web.eecs.umich.edu/~fessler/code/index.html)
    d=get_parent_path(which('addRetroMoCoBoxToPath'),2)
    run(fullfile(d,'/mirt/setup.m'))
end

if length(swallowMagnitude)==1
    swallowMagnitude = [swallowMagnitude swallowMagnitude];% first is translations, second is rotations
end
if length(suddenMagnitude)==1
    suddenMagnitude  = [suddenMagnitude suddenMagnitude];% first is translations, second is rotations
end

%%% Load input volume

[ vol , image_original] = nifti_spm_vol(fin);

% force dimension to be even for simplicity of consitent indexing:
[nx,ny,nz] = size(image_original);
nx = 2*floor(nx/2); ny = 2*floor(ny/2); nz = 2*floor(nz/2);
image_original = image_original(1:nx,1:ny,1:nz);
vol.dim = [nx ny nz];

% image_original = image_original(:,:,81:100); % <--- use only a subset of the data to be much faster

% normalize:
%image_original = image_original / percentile(abs(image_original),95);

rawData = fft3s(image_original);

nT = size(rawData,2);


[fitpars,RMS_displacement,RMS_rot ] = simul_displacement(...
    nT,noiseBasePars,maxDisp,maxRot,swallowFrequency,swallowMagnitude,suddenFrequency,suddenMagnitude,seed_num);

mat=vol(1).mat(1:3,1:3);
hostVoxDim_mm = sqrt(diag(mat'*mat));


% convert the motion parameters into a set off affine matrices:
fitMats = euler2rmat(fitpars(4:6,:));
fitMats(1:3,4,:) = fitpars(1:3,:);

% set some things for the recon function:
alignDim = 2; alignIndices = 1:nT; Hxyz = size(rawData); kspaceCentre_xyz = floor(Hxyz/2)+1;

% use the recon function just to extract the nufft 'object' st:
[~, st] = applyRetroMC_nufft(rawData,fitMats,alignDim,alignIndices,11,hostVoxDim_mm,Hxyz,kspaceCentre_xyz,-1);
% and use the nufft rather than the nufft_adj function to simulate the rotations:
image_simRotOnly = ifft3s(reshape(nufft(ifft3s(rawData),st),size(rawData)));
% then apply just the translations:
[~,~,image_simMotion] = applyRetroMC_nufft(fft3s(image_simRotOnly),fitMats,alignDim,alignIndices,11,hostVoxDim_mm,Hxyz,kspaceCentre_xyz,-1);

image_simMotion = ifft3s(image_simMotion);
%rrr no normalisation   image_simMotion = image_simMotion / percentile(abs(image_simMotion),95);


rms_round = round(( RMS_displacement + RMS_rot)/2 *100);

%find the prefix
file_prefix = sprintf('Motion_RMS_%d_Disp_%d_swalF_%d_swalM_%d_sudF_%d_sudM_%d_',...
    rms_round,round(maxDisp*100),round(swallowFrequency*100),round(swallowMagnitude*100),...
    round(suddenFrequency*100),round(suddenMagnitude*100));
    
fname = addprefixtofilenames(fout,  file_prefix);

fprintf('saving %s\n',fname);

fname = change_file_extension(fname,'.nii'); % in case of .gz input

vol.fname = fname;
vol.dt(1) = 4; %force int16
spm_write_vol(vol,abs(image_simMotion));

gzip_volume(fname)

    
c = corr(image_original(:),abs(image_simMotion(:))) ;
z = nmi(   round( image_original(:)),round(abs(image_simMotion(:)))) ;

x = round( image_original(:)); y = round(abs(image_simMotion(:))) ;
rmse = sqrt(sum((x-y).^2))./length(x);

fparam = change_file_extension(fname,'.csv');

ff = fopen(fparam,'w');
fprintf(ff,'filename, RMS, Disp, swalF, swalM, sudF, sudM, corr, nmi, rmse \n')
fprintf(ff,'%s,%f,%f,%f,%f,%f,%f,%f,%f,%f\n',fname, ( RMS_displacement + RMS_rot)/2  , ...
    maxDisp,swallowFrequency,swallowMagnitude(1),suddenFrequency,suddenMagnitude(1),c,z,rmse);
fclose(ff);

fparam = change_file_extension(fname,'.txt');
fparam = addprefixtofilenames(fparam,'rp_');

ff = fopen(fparam,'w');
for k=1:size(fitpars,1)
    fprintf(ff,'%f,',fitpars(k,:));
    fprintf(ff,'\n');
end
fclose(ff);





function z = nmi(x, y)
% Compute normalized mutual information I(x,y)/sqrt(H(x)*H(y)) of two discrete variables x and y.
% Input:
%   x, y: two integer vector of the same length 
% Ouput:
%   z: normalized mutual information z=I(x,y)/sqrt(H(x)*H(y))
% Written by Mo Chen (sth4nth@gmail.com).
assert(numel(x) == numel(y));
n = numel(x);
x = reshape(x,1,n);
y = reshape(y,1,n);

l = min(min(x),min(y));
x = x-l+1;
y = y-l+1;
k = max(max(x),max(y));

idx = 1:n;
Mx = sparse(idx,x,1,n,k,n);
My = sparse(idx,y,1,n,k,n);
Pxy = nonzeros(Mx'*My/n); %joint distribution of x and y
Hxy = -dot(Pxy,log2(Pxy));


% hacking, to elimative the 0log0 issue
Px = nonzeros(mean(Mx,1));
Py = nonzeros(mean(My,1));

% entropy of Py and Px
Hx = -dot(Px,log2(Px));
Hy = -dot(Py,log2(Py));

% mutual information
MI = Hx + Hy - Hxy;

% normalized mutual information
z = sqrt((MI/Hx)*(MI/Hy));
z = max(0,z);

