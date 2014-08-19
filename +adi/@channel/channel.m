classdef channel < sl.obj.display_class
    %
    %   Class:
    %   adi.channel
    %
    %   This class only holds information regarding the channel.
    
    properties
        id    %Internal number (1 based)
        name
        
        %These properties are on a per record basis ...
        %-----------------------------------------------
        units      %cellstr
        n_samples  %array - # of samples collected on this channel during
        %each record
        dt         %array - time between samples
        fs         %array - sampling rate (1/dt)
        
    end
    
    properties (Hidden)
        n_records
        file_h
        tick_dt
        record_handles
        sdk
        file_path
    end
    
    properties (Dependent)
        downsample_amount %How this channel relates to the fastest sampling
        %rate. If this is the fastest sampled channel, the value will be 1.
        %If the sampling rate is a tenth of the fastest, the value will be
        %10.
    end
    
    methods
        function value = get.downsample_amount(obj)
            value = obj.dt./obj.tick_dt;
        end
    end
    
    methods
        function obj = channel(file_h,sdk,channel_id,record_handles,file_path)
            %x adi.channel constructor
            %
            %   obj = adi.channel(file_h,id,n_records,tick_dt)
            %
            %
            
            obj.sdk            = sdk;
            obj.id             = channel_id;
            obj.n_records      = length(record_handles);
            obj.file_h         = file_h;
            obj.tick_dt        = [record_handles.tick_dt];
            obj.record_handles = record_handles;
            obj.file_path      = file_path;
            
            temp_sample_period = zeros(1,obj.n_records);
            temp_n_samples     = zeros(1,obj.n_records);
            temp_units         = cell(1,obj.n_records);
            
            obj.name = sdk.getChannelName(file_h,channel_id);
            
            for iRecord = 1:obj.n_records
                temp_sample_period(iRecord) = sdk.getSamplePeriod(file_h,iRecord,channel_id);
                temp_n_samples(iRecord)     = sdk.getNSamplesInRecord(file_h,iRecord,channel_id);
                temp_units{iRecord}         = sdk.getUnits(file_h,iRecord,channel_id);
            end
            
            obj.units     = temp_units;
            obj.n_samples = temp_n_samples;
            obj.dt        = temp_sample_period;
            obj.fs        = 1./(obj.dt);
        end
        
        %I'd like to remove this ...
        %------------------------------------------------------
        function comment_objs = getRecordComments(obj,record_id,varargin)
            %x Small helper to get the comments for a given record
            %
            %
            
            
            in.time_range = [];
            in.all_channels = true;
            in = adi.sl.in.processVarargin(in,varargin);
            
            comment_objs = obj.record_handles(record_id).comments;
            
            %
            if ~isempty(in.time_range) && ~isempty(comment_objs)
                comment_objs = comment_objs.filterByTime(in.time_range);
            end
            
            if ~in.all_channels && ~isempty(comment_objs)
                comment_objs = comment_objs.filterByChannel(in.time_range);
            end
            
            
        end
        
        %------------------------------------------------------
        
        
        function printChannelNames(objs)
            %x  Prints all channel names to the command window
            %
            %   printChannelNames(objs)
            
            for iObj = 1:length(objs)
                fprintf('%s\n',objs(iObj).name);
            end
        end
        function chan = getChannelByName(objs,name,varargin)
            %x  Finds and returns a channel object by name
            %
            %    chan = getChannelByName(objs,name)
            %
            %    Inputs:
            %    -------
            %    name: str
            %       Name of the channel to retrieve. Optional inputs
            %       dictate how this input is compared to the actual names
            %       of the channels.
            %
            %    Optional Inputs:
            %    ----------------
            %    case_sensitive: (default false)
            %    partial_match: (default true)
            %       If true the input only needs to be a part of the name.
            %       For example we could get the channel 'Bladder Pressure'
            %       by using the <name> 'pres' since 'pres' is in the
            %       string 'Bladder Pressure'
            %
            %    See Also:
            %    adi.file.getChannelByName
            
            in.case_sensitive = false;
            in.partial_match  = true;
            in = adi.sl.in.processVarargin(in,varargin);
            
            all_names = {objs.name};
            if ~in.case_sensitive
                all_names = lower(all_names);
                name      = lower(name);
            end
            
            if in.partial_match
                I = find(cellfun(@(x) adi.sl.str.contains(x,name),all_names));
            else
                %Could also use: sl.str.findSingularMatch
                I = find(strcmp(all_names,name));
            end
            
            if isempty(I)
                error('Unable to find channel with name: %s',name)
            elseif length(I) > 1
                error('Multiple matches for channel name found')
            end
            
            chan = objs(I);
        end
        function objs_with_data = removeEmptyObjects(objs)
            %x Removes channels with no data in them.
            %
            %   This is done by default on loading the channels so that
            %   empty channels don't clutter things up.
            %
            %   This can be disabled by changing the read options.
            %
            %   See also:
            %   adi.readFile
            
            n_objs    = length(objs);
            keep_mask = false(1,n_objs);
            for iObj = 1:n_objs
                keep_mask(iObj) = sum(objs(iObj).n_samples) ~= 0;
            end
            objs_with_data = objs(keep_mask);
        end
        function varargout = getData(obj,record_id,varargin)
            %
            %   Inputs:
            %   -------
            %   record_id:
            %       Record # from which to retrieve data.
            %
            %   Optional Inputs:
            %   ----------------
            %   return_object: (default true)
            %   data_range: [min max] (default full range)
            %   get_as_samples: (default true)
            %       If false the channel is upsampled to the highest rate
            %       using sample and hold.
            %   time_range: [min max]
            %       Often times it is more natural to specify a range of
            %       time over which to request the data, rather than a
            %       range of samples. Use this to specify the data that is
            %       between the specified min and max time values.
            %
            
            if record_id < 1 || record_id > obj.n_records
                error('Record input: %d, out of range: [1 %d]',record_id,obj.n_records);
            end
            
            
            
            in.return_object  = true;
            in.data_range     = [1 obj.n_samples(record_id)];
            in.time_range     = []; %Seconds, TODO: Document this ...
            in.get_as_samples = true; %Alternatively ...
            in.leave_raw      = false;
            in = sl.in.processVarargin(in,varargin);
            
            %TODO: This is not right if get_as_samples is false
            if isempty(in.time_range)
                %We populate this for comment retrieval
                in.time_range = (in.data_range-1)/obj.fs(record_id);
            else
                in.data_range(1) = floor(in.time_range(1)*obj.fs(record_id))+1;
                in.data_range(2) = ceil(in.time_range(2)*obj.fs(record_id))+1;
            end
            
            if any(in.data_range > obj.n_samples(record_id))
                error('Data requested out of range')
            end
            
            if in.data_range(1) > in.data_range(2)
                error('Specified data range must be increasing')
            end
            
            data = obj.sdk.getChannelData(...
                obj.file_h,...
                record_id,...
                obj.id,...
                in.data_range(1),...
                in.data_range(2)-in.data_range(1)+1,...
                in.get_as_samples,...
                'leave_raw',in.leave_raw);
            
            if isrow(data)
                data = data';
            end
            
            if in.return_object
                comments = obj.getRecordComments(record_id,'time_range',in.time_range);
                
                time_events = sci.time_series.time_events('comments',...
                    [comments.time],'values',[comments.id],...
                    'msgs',{comments.str});
                
                %TODO: This is not right if get_as_samples is false
                time_object = sci.time_series.time(...
                    obj.dt(record_id),...
                    length(data),...
                    'sample_offset',in.data_range(1));
                varargout{1} = sci.time_series.data(data,...
                    time_object,...
                    'units',obj.units{record_id},...
                    'channel_labels',obj.name,...
                    'history',sprintf('File: %s\nRecord: %d',obj.file_path,record_id),...
                    'events',time_events);
            else
                varargout{1} = data;
                if nargout == 2
                    varargout{2} = (0:(length(data)-1)).*obj.dt(record_id);
                end
            end
        end
    end
    methods (Hidden)
        exportToHDF5File(objs,fobj,save_path,conversion_options)
        function exportToMatFile(objs,m,conversion_options)
            
            MAX_SAMPLES_AT_ONCE = 1e7;
            
            m.channel_version = 1;
            
            m.channel_meta = struct(...
                'id',        {objs.id},...
                'name',      {objs.name},...
                'units',     {objs.units},...
                'n_samples', {objs.n_samples},...
                'dt',        {objs.dt});
            
            %NOTE: It would be nice to be able to save the raw data ...
            %-----------------------------------
            m.data_version = 1;
            
            %NOTE: We can't go deeper than a single element :/
            
            n_objs    = length(objs);
            n_records = objs(1).n_records; %#ok<PROP>
            for iChan = 1:n_objs
                cur_chan = objs(iChan);
                for iRecord = 1:n_records %#ok<PROP>
                    cur_n_samples = cur_chan.n_samples(iRecord);
                    chan_name = sprintf('data__chan_%d_rec_%d',iChan,iRecord);
                    if cur_n_samples < MAX_SAMPLES_AT_ONCE
                        %(obj,record_id,get_as_samples)
                        m.(chan_name) = cur_chan.getAllData(iRecord,'leave_raw',true);
                    else
                        
                        start_I = 1:MAX_SAMPLES_AT_ONCE:cur_n_samples;
                        end_I   = MAX_SAMPLES_AT_ONCE:MAX_SAMPLES_AT_ONCE:cur_n_samples;
                        
                        if length(end_I) < length(start_I)
                            end_I(end+1) = cur_n_samples; %#ok<AGROW>
                        end
                        
                        m.(chan_name)(cur_n_samples,1) = 0; %Initialize output
                        for iChunk = 1:length(start_I)
                            cur_start = start_I(iChunk);
                            cur_end   = end_I(iChunk);
                            n_samples_get = cur_end-cur_start + 1;
                            m.(chan_name)(cur_start:cur_end,1) = cur_chan.getDataSubset(iRecord,cur_start,n_samples_get,'leave_raw',true);
                        end
                    end
                end
            end
        end
    end
    
end
