class Ntfs3gFuset < Formula
  desc "Read-write NTFS driver built against FUSE-T (kextless FUSE)"
  homepage "https://github.com/macos-fuse-t/ntfs-3g"
  url "https://github.com/macos-fuse-t/ntfs-3g/archive/f0e5cb0274e30334dd03aefb4fd5a14c239e6756.tar.gz"
  sha256 "911cec6d9015aa5d41579dfc4a606784179cb28e4341fb15d52173d8cc17fd2a"
  license all_of: ["GPL-2.0-or-later", "LGPL-2.0-or-later"]
  version "2022.10.3-fuset"

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "libgcrypt" => :build
  depends_on "pkgconf" => :build
  depends_on "gettext"
  depends_on :macos

  def install
    # FUSE-T 설치 경로: 시스템(/usr/local) 또는 유저스페이스(~/.fuse-t/usr/local)
    # 빌드 프로세스는 HOME이 스크럽되므로 passwd 엔트리로 실제 홈을 얻는다
    require "etc"
    real_home = Etc.getpwuid.dir
    fuset_prefix = ["/usr/local", "#{real_home}/.fuse-t/usr/local"].find do |p|
      Dir.glob("#{p}/lib/libfuse-t*.dylib").any?
    end
    odie "FUSE-T가 설치되어 있지 않습니다. `Scripts/install-deps.sh` 또는 `brew install --cask fuse-t`를 실행하세요." unless fuset_prefix

    fuset_lib = "#{fuset_prefix}/lib"
    fuset_include = "#{fuset_prefix}/include/fuse"

    # -lfuse-t는 넣지 않는다: 링크된 conftest가 brew 샌드박스에서 trap으로 죽음.
    # ntfs-3g fork의 Makefile.am이 FUSE_LIBS=-lfuse-t를 자체적으로 넣어준다.
    ENV.append "CPPFLAGS", "-I#{fuset_include}"
    ENV.append "LDFLAGS", "-L#{fuset_lib} -Wl,-rpath,#{fuset_lib} -Wl,-rpath,/usr/local/lib -lintl"

    system "./autogen.sh"
    system "./configure",
           "--exec-prefix=#{prefix}",
           "--mandir=#{man}",
           "--with-fuse=external",
           "--enable-extras",
           "--disable-ldconfig",
           *std_configure_args
    system "make"
    system "make", "install"
  end

  def caveats
    <<~EOS
      ntfs-3g는 root 권한이 필요합니다:
        sudo ntfs-3g /dev/diskXsY /Volumes/NAME -o local,allow_other
    EOS
  end
end
