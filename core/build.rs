use std::{env, path::PathBuf, process::Command};

fn main() {
    println!("cargo:rerun-if-changed=src/claude_signal.c");
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR"));
    let object = out.join("claude_signal.o");
    let archive = out.join("librium_claude_signal.a");
    let target = env::var("TARGET").expect("TARGET");
    let status = Command::new("xcrun").args(["clang", "-target", &target, "-c", "src/claude_signal.c", "-o"])
        .arg(&object).status().expect("clang 실행 실패");
    assert!(status.success(), "Claude 신호 확인 코드 컴파일 실패");
    let status = Command::new("xcrun").args(["ar", "crs"]).arg(&archive).arg(&object)
        .status().expect("ar 실행 실패");
    assert!(status.success(), "Claude 신호 확인 코드 연결 준비 실패");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=rium_claude_signal");
}
