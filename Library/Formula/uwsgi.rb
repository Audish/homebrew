require 'formula'

class Uwsgi < Formula
  url 'http://projects.unbit.it/downloads/uwsgi-0.9.6.2.tar.gz'
  homepage 'http://projects.unbit.it/uwsgi/'
  md5 'eab88c552e4c7c4ecb5188cdefc43390'

  def patches
    # Prevent the master process from closing all sockets before forking, instead, set FD_CLOEXEC
    # See http://projects.unbit.it/hg/uwsgi/rev/e935214d385a
    DATA
  end

  def install
    # Find the arch for the Python we are building against.
    # We remove 'ppc' support, so we can pass Intel-optimized CFLAGS.
    archs = archs_for_command("python")
    archs.remove_ppc!
    flags = archs.as_arch_flags

    ENV.append 'CFLAGS', flags
    ENV.append 'LDFLAGS', flags

    inreplace 'uwsgiconfig.py', "PYLIB_PATH = ''", "PYLIB_PATH = '#{%x[python-config --ldflags].chomp[/-L(.*?) -l/, 1]}'"

    system "python uwsgiconfig.py --build"
    bin.install "uwsgi"
  end

  def caveats
    <<-EOS.undent
      NOTE: "brew install -v uwsgi" will fail!
      You must install in non-verbose mode for this to succeed.
      Patches to fix this are welcome.
    EOS
  end
end

__END__
diff --git a/uwsgi.c b/uwsgi.c
index c73fc5f..727c74e 100644
--- a/uwsgi.c
+++ b/uwsgi.c
@@ -1368,7 +1368,11 @@ int main(int argc, char *argv[], char *envp[]) {
 					if (i == uwsgi.serverfd) {
 						continue;
 					}
+#ifdef __APPLE__
+					fcntl(i, F_SETFD, FD_CLOEXEC);  
+#else
 					close(i);
+#endif
 				}
 				if (uwsgi.serverfd != 3) {
 					if (dup2(uwsgi.serverfd, 3) < 0) {
