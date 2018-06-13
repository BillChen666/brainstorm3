function varargout = process_spikesorting_supervised( varargin )
% PROCESS_SPIKESORTING_SUPERVISED:
% This process opens up a supervised Spike Sorting program allowing for
% manual correction of unsupervised spike sorted events.
%
% USAGE: OutputFiles = process_spikesorting_supervised('Run', sProcess, sInputs)

% @=============================================================================
% This function is part of the Brainstorm software:
% http://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2018 University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Authors: Martin Cousineau, 2018

eval(macro_method);
end


%% ===== GET DESCRIPTION =====
function sProcess = GetDescription() %#ok<DEFNU>
    % Description the process
    sProcess.Comment     = 'Supervised spike sorting';
    sProcess.Category    = 'Custom';
    sProcess.SubGroup    = 'Electrophysiology';
    sProcess.Index       = 1202;
    sProcess.Description = 'www.in.gr';
    % Definition of the input accepted by this process
    sProcess.InputTypes  = {'raw'};
    sProcess.OutputTypes = {'raw'};
    sProcess.nInputs     = 1;
    sProcess.nMinFiles   = 1;
    sProcess.isSeparator = 1;
end


%% ===== FORMAT COMMENT =====
function Comment = FormatComment(sProcess) %#ok<DEFNU>
    Comment = sProcess.Comment;
end


%% ===== RUN =====
function OutputFiles = Run(sProcess, sInputs) %#ok<DEFNU>
    global GlobalData;
    OutputFiles = {};
    ProtocolInfo = bst_get('ProtocolInfo');
    
    % Compute on each raw input independently
    for i = 1:length(sInputs)
        sInput = sInputs(i);
        DataMat = in_bst_data(sInput.FileName);
        
        % Make sure spikes exist and were generated by WaveClus
        if ~isfield(DataMat, 'Spikes') || ~isstruct(DataMat.Spikes) ...
                || ~isfield(DataMat, 'Parent') ...
                || exist(DataMat.Parent, 'dir') ~= 7 ...
                || isempty(dir(DataMat.Parent))
            bst_report('Error', sProcess, sInput, ...
                'No spikes found. Make sure to run the unsupervised Spike Sorter first.');
            return;
        end

        switch lower(DataMat.Device)
            case 'waveclus'
                % Ensure we are including the WaveClus folder in the Matlab path
                waveclusDir = bst_fullfile(bst_get('BrainstormUserDir'), 'waveclus');
                if exist(waveclusDir, 'file')
                    addpath(genpath(waveclusDir));
                end

                % Install WaveClus if missing
                if ~exist('wave_clus_font', 'file')
                    rmpath(genpath(waveclusDir));
                    isOk = java_dialog('confirm', ...
                        ['The WaveClus spike-sorter is not installed on your computer.' 10 10 ...
                             'Download and install the latest version?'], 'WaveClus');
                    if ~isOk
                        bst_report('Error', sProcess, sInputs, 'This process requires the WaveClus spike-sorter.');
                        return;
                    end
                    process_spikesorting_waveclus('downloadAndInstallWaveClus');
                end

            case 'ultramegasort2000'
                % Ensure we are including the UltraMegaSort2000 folder in the Matlab path
                UltraMegaSort2000Dir = bst_fullfile(bst_get('BrainstormUserDir'), 'UltraMegaSort2000');
                if exist(UltraMegaSort2000Dir, 'file')
                    addpath(genpath(UltraMegaSort2000Dir));
                end

                if ~exist('ss_default_params', 'file')
                    rmpath(genpath(UltraMegaSort2000Dir));
                    isOk = java_dialog('confirm', ...
                        ['The UltraMegaSort2000 spike-sorter is not installed on your computer.' 10 10 ...
                             'Download and install the latest version?'], 'UltraMegaSort2000');
                    if ~isOk
                        bst_report('Error', sProcess, sInputs, 'This process requires the UltraMegaSort2000 spike-sorter.');
                        return;
                    end
                    process_spikesorting_ultramegasort2000('downloadAndInstallUltraMegaSort2000');
                end

            otherwise
                bst_error('The chosen spike sorter is currently unsupported by Brainstorm.');
        end
        
        CloseFigure();
        
        GlobalData.SpikeSorting = struct();
        GlobalData.SpikeSorting.Data = DataMat;
        GlobalData.SpikeSorting.Selected = 0;
        GlobalData.SpikeSorting.Fig = -1;
        
        gui_brainstorm('ShowToolTab', 'Spikes');
        OpenFigure();
        panel_spikes('UpdatePanel');
    end
    
end

function OpenFigure()
    global GlobalData;
    
    bst_progress('start', 'Spike Sorting', 'Loading spikes...');
    CloseFigure();
    
    GlobalData.SpikeSorting.Selected = GetNextElectrode();
    
    electrodeFile = bst_fullfile(...
        GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).Path, ...
        GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).File);
    
    switch lower(GlobalData.SpikeSorting.Data.Device)
        case 'waveclus'
            GlobalData.SpikeSorting.Fig = wave_clus(electrodeFile);
            
            % Some Wave Clus visual hacks
            load_button = findall(GlobalData.SpikeSorting.Fig, 'Tag', 'load_data_button');
            if ishandle(load_button)
                load_button.Visible = 'off';
            end
            save_button = findall(GlobalData.SpikeSorting.Fig, 'Tag', 'save_clusters_button');
            if ishandle(save_button)
                save_button.Visible = 'off';
            end

        case 'ultramegasort2000'
            DataMat = load(electrodeFile, 'spikes');
            GlobalData.SpikeSorting.Fig = figure('Units', 'Normalized', 'Position', ...
                DataMat.spikes.params.display.default_figure_size);
            % Just open figure, rest of the code in LoadElectrode()
        otherwise
            bst_error('This spike sorting structure is currently unsupported by Brainstorm.');
    end
    
    panel_spikes('UpdatePanel');
    LoadElectrode();
    
    % Close Spike panel when you close the figure
    function my_closereq(src, callbackdata)
        delete(src);
        panel_spikes('UpdatePanel');
    end
    GlobalData.SpikeSorting.Fig.CloseRequestFcn = @my_closereq;
    
    bst_progress('stop');
end

function isOpen = FigureIsOpen()
    global GlobalData;
    isOpen = isfield(GlobalData, 'SpikeSorting') ...
        && isfield(GlobalData.SpikeSorting, 'Fig') ...
        && ishandle(GlobalData.SpikeSorting.Fig);
end

function CloseFigure()
    global GlobalData;
    if ~FigureIsOpen()
        return;
    end
    
    close(GlobalData.SpikeSorting.Fig);
    panel_spikes('UpdatePanel');
end

function LoadElectrode()
    global GlobalData;
    if ~FigureIsOpen()
        return;
    end
    
    electrodeFile = bst_fullfile(...
        GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).Path, ...
        GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).File);
    
    switch lower(GlobalData.SpikeSorting.Data.Device)
        case 'waveclus'
            wave_clus('load_data_button_Callback', GlobalData.SpikeSorting.Fig, ...
                electrodeFile, guidata(GlobalData.SpikeSorting.Fig));
            
            name_text = findall(GlobalData.SpikeSorting.Fig, 'Tag', 'file_name');
            if ishandle(name_text)
                name_text.String = panel_spikes('GetSpikeName', GlobalData.SpikeSorting.Selected); 
            end

        case 'ultramegasort2000'
            % Reload figure altogether, same behavior as builtin load...
            DataMat = load(electrodeFile, 'spikes');
            clf(GlobalData.SpikeSorting.Fig, 'reset');
            splitmerge_tool(DataMat.spikes, 'all', GlobalData.SpikeSorting.Fig);
            
            % Some UMS2k visual hacks
            save_button = findall(GlobalData.SpikeSorting.Fig, 'Tag', 'saveButton');
            if ishandle(save_button)
                save_button.Visible = 'off';
            end
            save_button = findall(GlobalData.SpikeSorting.Fig, 'Tag', 'saveFileButton');
            if ishandle(save_button)
                save_button.Visible = 'off';
            end
            load_button = findall(GlobalData.SpikeSorting.Fig, 'Tag', 'loadFileButton');
            if ishandle(load_button)
                load_button.Visible = 'off';
            end
            
        otherwise
            bst_error('This spike sorting structure is currently unsupported by Brainstorm.');
    end
end

function SaveElectrode()
    global GlobalData;
    
    if ~FigureIsOpen()
        return;
    end
    
    electrodeFile = bst_fullfile(...
        GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).Path, ...
        GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).File);
    
    % Save through Spike Sorting software
    switch lower(GlobalData.SpikeSorting.Data.Device)
        case 'waveclus'
            % WaveClus takes a screenshot of the figure when saving, which
            % is pretty slow. If we change the figure tag it skips this.
            save_button = findall(GlobalData.SpikeSorting.Fig, 'Tag', 'save_clusters_button');
            fig_tag = GlobalData.SpikeSorting.Fig.Tag;
            GlobalData.SpikeSorting.Fig.Tag = 'wave_clus_tmp';
            wave_clus('save_clusters_button_Callback', save_button, ...
                [], guidata(GlobalData.SpikeSorting.Fig), 0);
            GlobalData.SpikeSorting.Fig.Tag = fig_tag;

        case 'ultramegasort2000'
            figdata = get(GlobalData.SpikeSorting.Fig, 'UserData');
            spikes = figdata.spikes;
            save(electrodeFile, 'spikes');
            OutMat = struct();
            OutMat.pathname = GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).Path;
            OutMat.filename = GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).File;
            set(figdata.sfb, 'UserData', OutMat);

        otherwise
            bst_error('This spike sorting structure is currently unsupported by Brainstorm.');
    end
    
    % Save updated brainstorm file
    GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).Mod = 1;
    bst_save(GlobalData.SpikeSorting.Data.Name, GlobalData.SpikeSorting.Data, 'v6');
    
    % Add event to linked raw file    
    CreateSpikeEvents(GlobalData.SpikeSorting.Data.RawFile, ...
        GlobalData.SpikeSorting.Data.Device, ...
        electrodeFile, ...
        GlobalData.SpikeSorting.Data.Spikes(GlobalData.SpikeSorting.Selected).Name, ...
        1);
end

function nextElectrode = GetNextElectrode()
    global GlobalData;
    if ~isfield(GlobalData, 'SpikeSorting') ...
            || ~isfield(GlobalData.SpikeSorting, 'Selected') ...
            || isempty(GlobalData.SpikeSorting.Selected)
        GlobalData.SpikeSorting.Selected = 0;
    end
    
    numSpikes = length(GlobalData.SpikeSorting.Data.Spikes);
    
    if GlobalData.SpikeSorting.Selected < numSpikes
        nextElectrode = GlobalData.SpikeSorting.Selected + 1;
        while nextElectrode <= numSpikes && ...
                isempty(GlobalData.SpikeSorting.Data.Spikes(nextElectrode).File)
            nextElectrode = nextElectrode + 1;
        end
    end
    if nextElectrode >= numSpikes || isempty(GlobalData.SpikeSorting.Data.Spikes(nextElectrode).File)
        nextElectrode = GlobalData.SpikeSorting.Selected;
    end
end

function newEvents = CreateSpikeEvents(rawFile, deviceType, electrodeFile, electrodeName, import, eventNamePrefix)
    if nargin < 6
        eventNamePrefix = '';
    else
        eventNamePrefix = [eventNamePrefix ' '];
    end
    newEvents = struct();
    DataMat = in_bst_data(rawFile);
    eventName = [eventNamePrefix GetSpikesEventPrefix() ' ' electrodeName];

    % Load spike data and convert to Brainstorm event format
    switch lower(deviceType)
        case 'waveclus'
            if exist(electrodeFile, 'file') == 2
                ElecData = load(electrodeFile, 'cluster_class');
                neurons = unique(ElecData.cluster_class(ElecData.cluster_class(:,1) > 0,1));
                numNeurons = length(neurons);
                tmpEvents = struct();
                if numNeurons == 1
                    tmpEvents(1).epochs = ones(1, sum(ElecData.cluster_class(:,1) ~= 0));
                    tmpEvents(1).times = ElecData.cluster_class(ElecData.cluster_class(:,1) ~= 0, 2)' ./ 1000;
                else
                    for iNeuron = 1:numNeurons
                        tmpEvents(iNeuron).epochs = ones(1, length(ElecData.cluster_class(ElecData.cluster_class(:,1) == iNeuron, 1)));
                        tmpEvents(iNeuron).times = ElecData.cluster_class(ElecData.cluster_class(:,1) == iNeuron, 2)' ./ 1000;
                    end
                end
            else
                numNeurons = 0;
            end

        case 'ultramegasort2000'
            ElecData = load(electrodeFile, 'spikes');
            ElecData.spikes.spiketimes = double(ElecData.spikes.spiketimes);
            numNeurons = size(ElecData.spikes.labels,1);
            tmpEvents = struct();
            if numNeurons == 1
                tmpEvents(1).epochs = ones(1,length(ElecData.spikes.assigns));
                tmpEvents(1).times = ElecData.spikes.spiketimes;
            elseif numNeurons > 1
                for iNeuron = 1:numNeurons
                    tmpEvents(iNeuron).epochs = ones(1,length(ElecData.spikes.assigns(ElecData.spikes.assigns == ElecData.spikes.labels(iNeuron,1))));
                    tmpEvents(iNeuron).times = ElecData.spikes.spiketimes(ElecData.spikes.assigns == ElecData.spikes.labels(iNeuron,1));
                end
            end
            
        otherwise
            bst_error('This spike sorting structure is currently unsupported by Brainstorm.');
    end
    
    if numNeurons == 1
        newEvents(1).label      = eventName;
        newEvents(1).color      = [rand(1,1), rand(1,1), rand(1,1)];
        newEvents(1).epochs     = tmpEvents(1).epochs;
        newEvents(1).times      = tmpEvents(1).times;
        newEvents(1).samples    = round(newEvents(1).times .* DataMat.F.prop.sfreq);
        newEvents(1).reactTimes = [];
        newEvents(1).select     = 1;
    elseif numNeurons > 1
        for iNeuron = 1:numNeurons
            newEvents(iNeuron).label      = [eventName ' |' num2str(iNeuron) '|'];
            newEvents(iNeuron).color      = [rand(1,1), rand(1,1), rand(1,1)];
            newEvents(iNeuron).epochs     = tmpEvents(iNeuron).epochs;
            newEvents(iNeuron).times      = tmpEvents(iNeuron).times;
            newEvents(iNeuron).samples    = round(newEvents(iNeuron).times .* DataMat.F.prop.sfreq);
            newEvents(iNeuron).reactTimes = [];
            newEvents(iNeuron).select     = 1;
        end
    else
        % This electrode just picked up noise, no event to add.
        newEvents(1).label      = eventName;
        newEvents(1).color      = [rand(1,1), rand(1,1), rand(1,1)];
        newEvents(1).epochs     = [];
        newEvents(1).times      = [];
        newEvents(1).samples    = [];
        newEvents(1).reactTimes = [];
        newEvents(1).select     = 1;
    end

    if import
        ProtocolInfo = bst_get('ProtocolInfo');
        % Add event to linked raw file
        numEvents = length(DataMat.F.events);
        % Delete existing event(s)
        if numEvents > 0
            iDelEvents = cellfun(@(x) ~isempty(x), strfind({DataMat.F.events.label}, eventName));
            DataMat.F.events = DataMat.F.events(~iDelEvents);
            numEvents = length(DataMat.F.events);
        end
        % Add as new event(s);
        for iEvent = 1:length(newEvents)
            DataMat.F.events(numEvents + iEvent) = newEvents(iEvent);
        end
        bst_save(bst_fullfile(ProtocolInfo.STUDIES, rawFile), DataMat, 'v6');
    end
end

function prefix = GetSpikesEventPrefix()
    prefix = 'Spikes Channel';
end

function isSpikeEvent = IsSpikeEvent(eventLabel)
    prefix = GetSpikesEventPrefix();
    isSpikeEvent = strncmp(eventLabel, prefix, length(prefix));
end

function neuron = GetNeuronOfSpikeEvent(eventLabel)
    markers = strfind(eventLabel, '|');
    if length(markers) > 1
        neuron = str2num(eventLabel(markers(end-1)+1:markers(end)-1));
    else
        neuron = [];
    end
end

function channel = GetChannelOfSpikeEvent(eventLabel)
    eventLabel = strtrim(eventLabel);
    prefix = GetSpikesEventPrefix();
    neuron = GetNeuronOfSpikeEvent(eventLabel);
    bounds = [length(prefix) + 2, 0]; % 'Spikes Channel '
    
    if ~isempty(neuron)
        bounds(2) = length(num2str(neuron)) + 3; % ' |31|'
    end
    
    try
        channel = eventLabel(bounds(1):end-bounds(2));
    catch
        channel = [];
    end
end

function isFirst = IsFirstNeuron(eventLabel, onlyIsFirst)
    % onlyIsFirst = We assume a channel with a single neuron counts as a first neuron.
    if nargin < 2
        onlyIsFirst = 1;
    end
    
    neuron = GetNeuronOfSpikeEvent(eventLabel);
    isFirst = neuron == 1;
    if onlyIsFirst && isempty(neuron)
        isFirst = 1;
    end
end
