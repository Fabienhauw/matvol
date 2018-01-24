function [ SPMstruct ] = load( modelArray )
%LOAD the 'SPM' variable of the SPM.mat file in the current workspace

SPMstruct = cell(numel(modelArray),1);

for idx = 1 : numel(modelArray)
    
    s = load(modelArray(idx).path, 'SPM');
    SPMstruct{idx} = s.SPM;

end % for all objects in modelArray

end % function
