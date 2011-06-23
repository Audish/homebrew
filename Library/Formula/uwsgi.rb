require 'formula'

class Uwsgi < Formula
  url 'http://projects.unbit.it/downloads/uwsgi-0.9.7.2.tar.gz'
  homepage 'http://projects.unbit.it/uwsgi/'
  md5 '9bdf8ed5c8b32ace085dbd0f9488f880'

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
diff --git a/master.c b/master.c
index 7e6f2f3..e71d72f 100644
--- a/master.c
+++ b/master.c
@@ -438,7 +438,11 @@ void master_loop(char **argv, char **environ) {
 					}
 				}
 				if (!found) {
+#ifdef __APPLE__
+					fcntl(i, F_SETFD, FD_CLOEXEC);
+#else
 					close(i);
+#endif
 				}
 			}

diff --git a/plugins/python/uwsgi_pymodule.c b/plugins/python/uwsgi_pymodule.c
--- a/plugins/python/uwsgi_pymodule.c
+++ b/plugins/python/uwsgi_pymodule.c
@@ -2182,7 +2182,6 @@
 
	pid_t grunt_pid;
	int i;
-	struct wsgi_request *wsgi_req = current_wsgi_req();
 
	if (uwsgi.grunt) {
		uwsgi_log("spawning a grunt from worker %d (pid :%d)...\n", uwsgi.mywid, uwsgi.mypid);
@@ -2218,10 +2217,6 @@
		return Py_True;
	}
 
-	// close connection on the worker
-	fclose(wsgi_req->async_post);
-	wsgi_req->fd_closed = 1;
-
       clear:
	Py_INCREF(Py_None);
	return Py_None;
