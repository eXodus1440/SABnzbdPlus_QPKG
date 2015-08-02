# SABnzbdPlus_QPKG
SABnzbdPlus qpkg for QNAP

Steps required to build the package on a QNAP TVS:

    git clone https://github.com/eXodus1440/SABnzbdPlus_QPKG.git SABnzbdPlus
    cd SABnzbdPlus 
    wget http://downloads.sourceforge.net/project/sabnzbdplus/sabnzbdplus/0.7.20/SABnzbd-0.7.20-src.tar.gz

    wget http://chuchusoft.com/par2_tbb/par2cmdline-0.4-tbb-20141125-lin64.tar.gz
    wget http://www.rarlab.com/rar/unrarsrc-5.2.7.tar.gz
    wget http://www.rarlab.com/rar/WinRARLinux.tar.gz

    tar -zxvf SABnzbd-0.7.20-src.tar.gz -C ./shared --strip-components=1
    qbuild --exclude solaris --exclude *.cmd
