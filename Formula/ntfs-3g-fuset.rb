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
    # FUSE-T 기본 설치 경로. 개발/테스트용으로 NTFS3G_FUSET_PREFIX 오버라이드 가능.
    fuset_prefix = ENV["NTFS3G_FUSET_PREFIX"] || "/usr/local"
    fuset_lib = "#{fuset_prefix}/lib"
    fuset_include = "#{fuset_prefix}/include/fuse"

    unless File.exist?("#{fuset_lib}/libfuse-t.dylib") || File.exist?("#{fuset_lib}/libfuse-t-1.2.7.dylib")
      odie "FUSE-T가 설치되어 있지 않습니다. 먼저 `brew install --cask fuse-t`를 실행하세요."
    end

    ENV.append "CPPFLAGS", "-I#{fuset_include}"
    ENV.append "LDFLAGS", "-L#{fuset_lib} -lfuse-t -Wl,-rpath,#{fuset_lib} -Wl,-rpath,/usr/local/lib -lintl"

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
