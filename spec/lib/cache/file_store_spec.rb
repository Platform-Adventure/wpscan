# frozen_string_literal: true

describe WPScan::Cache::FileStore do
  subject(:cache) { described_class.new(storage_path) }

  let(:tmp_dir)      { Dir.mktmpdir }
  let(:storage_path) { File.join(tmp_dir, 'cache', 'entries') }
  let(:key)          { 'key' }

  after { FileUtils.rm_rf(tmp_dir) }

  def plant_entry(content)
    File.write(cache.entry_path(key), content)
    File.write(cache.entry_expiration_path(key), Time.now.to_i + 3600)
  end

  describe '#initialize' do
    context 'when the storage path does not exist' do
      it 'creates it, and the missing parents, only accessible by the current user' do
        expect(File.stat(cache.storage_path).mode & 0o777).to eql 0o700
        expect(File.stat(File.dirname(cache.storage_path)).mode & 0o777).to eql 0o700
      end
    end

    context 'when the storage path is writable by others' do
      before do
        FileUtils.mkdir_p(storage_path)
        File.chmod(0o777, storage_path)
      end

      it 'raises an error' do
        expect { cache }.to raise_error(WPScan::Error::InsecureCacheDirectory, /writable by group or others/)
      end
    end

    context 'when the storage path is writable by the group' do
      before do
        FileUtils.mkdir_p(storage_path)
        File.chmod(0o770, storage_path)
      end

      it 'raises an error' do
        expect { cache }.to raise_error(WPScan::Error::InsecureCacheDirectory, /writable by group or others/)
      end
    end

    context 'when the storage path is not owned by the current user' do
      before do
        FileUtils.mkdir_p(storage_path)
        File.chmod(0o777, storage_path)

        allow(Process).to receive(:euid).and_return(Process.euid + 4242)
      end

      it 'raises an error' do
        expect { cache }.to raise_error(WPScan::Error::InsecureCacheDirectory, /not owned by the current user/)
      end
    end

    context 'when a parent directory is writable by others' do
      before do
        FileUtils.mkdir_p(storage_path, mode: 0o700)
        File.chmod(perms, File.dirname(storage_path))
      end

      context 'without the sticky bit' do
        let(:perms) { 0o777 }

        it 'raises an error' do
          expect { cache }.to raise_error(WPScan::Error::InsecureCacheDirectory, /does not have the sticky bit/)
        end
      end

      context 'with the sticky bit' do
        let(:perms) { 0o1777 }

        it 'does not raise an error' do
          expect { cache }.not_to raise_error
        end
      end
    end

    context 'when a parent directory is only writable by the group' do
      before do
        FileUtils.mkdir_p(storage_path, mode: 0o700)
        File.chmod(0o770, File.dirname(storage_path))
      end

      it 'does not raise an error' do
        expect { cache }.not_to raise_error
      end
    end

    context 'when the storage path is a symlink to an insecure directory' do
      let(:target_dir) { File.join(tmp_dir, 'shared') }

      before do
        FileUtils.mkdir_p(target_dir)
        File.chmod(0o777, target_dir)
        FileUtils.mkdir_p(File.dirname(storage_path), mode: 0o700)
        File.symlink(target_dir, storage_path)
      end

      it 'raises an error' do
        expect { cache }.to raise_error(WPScan::Error::InsecureCacheDirectory, /writable by group or others/)
      end
    end
  end

  describe '#write_entry' do
    it 'stores the data as JSON' do
      cache.write_entry(key, { 'a' => [1, 'b'] }, 60)

      expect(JSON.parse(File.read(cache.entry_path(key)))).to eql('a' => [1, 'b'])
      expect(cache.read_entry(key)).to eql('a' => [1, 'b'])
    end

    context 'when the cache_ttl is not positive' do
      it 'does not store anything' do
        cache.write_entry(key, 'data', 0)

        expect(Dir.children(cache.storage_path)).to be_empty
      end
    end
  end

  describe '#read_entry' do
    context 'when the entry is expired' do
      it 'returns nil' do
        cache.write_entry(key, 'data', 60)
        File.write(cache.entry_expiration_path(key), Time.now.to_i - 1)

        expect(cache.read_entry(key)).to be_nil
      end
    end

    context 'when the entry is a Marshal dump' do
      it 'does not load it with Marshal and returns nil' do
        plant_entry(Marshal.dump('data'))

        expect(Marshal).not_to receive(:load)
        expect(cache.read_entry(key)).to be_nil
      end
    end

    context 'when the entry is a JSON object with a json_class' do
      it 'does not instantiate the class' do
        plant_entry('{"json_class":"OpenStruct","a":1}')

        expect(cache.read_entry(key)).to eql('json_class' => 'OpenStruct', 'a' => 1)
      end
    end
  end
end
