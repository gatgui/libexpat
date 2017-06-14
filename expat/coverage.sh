#! /bin/bash
# Copyright (C) Sebastian Pipping <sebastian@pipping.org>
# Licensed under the MIT license

export PS4='# '


_get_source_dir() {
    echo "source__${version}"
}


_get_build_dir() {
    echo "build__${version}__unicode_${unicode_enabled}__xml_context_${xml_context}"
}


_get_coverage_dir() {
    echo "coverage__${version}"
}


_configure() {
    local configure_args=()

    ${unicode_enabled} \
            && configure_args+=( CPPFLAGS='-DXML_UNICODE -DXML_UNICODE_WCHAR_T' )

    if [[ ${xml_context} -eq 0 ]]; then
        configure_args+=( --disable-xml-context )
    else
        configure_args+=( --enable-xml-context=${xml_context} )
    fi

    (
        set -x
        ./buildconf.sh &> configure.log
        ./configure "${configure_args[@]}" "$@" &>> configure.log
    )
}


_copy_to() {
    local target_dir="$1"
    [[ -d "${target_dir}" ]] && return 0

    mkdir "${target_dir}"
    git archive --format=tar "${version}" | ( cd "${target_dir}" && tar x )
}


_run() {
    local source_dir="$1"
    local build_dir="$2"
    local capture_dir=lib

    local BASE_FLAGS='-pipe -Wall -Wextra -pedantic -Wno-overlength-strings'
    BASE_FLAGS+=' --coverage --no-inline'

    local CFLAGS="-std=c89 ${BASE_FLAGS}"
    local CXXFLAGS="-std=c++98 ${BASE_FLAGS}"

    (
        set -e
        cd "${build_dir}"

        _configure \
                CFLAGS="${BASE_FLAGS}" \
                CXXFLAGS="${BASE_FLAGS}"

        set -x
        make buildlib &> build.log

        lcov -c -d "${capture_dir}" -i -o "${coverage_info}-zero" &> run.log

        make check run-xmltest

        lcov -c -d "${capture_dir}" -o "${coverage_info}-test" &>> run.log
        lcov \
                -a "${coverage_info}-zero" \
                -a "${coverage_info}-test" \
                -o "${coverage_info}-all" \
                &>> run.log

        # Make sure that files overlap in report despite different build folders
        sed "/SF:/ s,${build_dir}/,${source_dir}/," "${coverage_info}-all" > "${coverage_info}"
    ) |& sed 's,^,  ,'
    res=${PIPESTATUS[0]}

    if [[ ${res} -eq 0 ]]; then
        echo PASSED
    else
        echo FAILED >&2
        return 1
    fi
}


_merge_coverage_info() {
    local coverage_dir="$1"
    shift
    local build_dirs=( "$@" )

    mkdir -p "${coverage_dir}"
    (
        local lcov_merge_args=()
        for build_dir in "${build_dirs[@]}"; do
            lcov_merge_args+=( -a "${build_dir}/${coverage_info}" )
        done
        lcov_merge_args+=( -o "${coverage_dir}/${coverage_info}" )

        set -x
        lcov "${lcov_merge_args[@]}"
    ) &> "${coverage_dir}/merge.log"
}


_render_html_report() {
    local coverage_dir="$1"
    genhtml -o "${coverage_dir}" "${coverage_dir}/${coverage_info}" &> "${coverage_dir}/render.log"
}


_show_summary() {
    local coverage_dir="$1"
    lcov -q -l "${coverage_dir}/${coverage_info}" | grep -v '^\['
}


_main() {
    version="$(git describe --tags)"
    coverage_info=coverage.info

    local build_dirs=()
    local source_dir="$(_get_source_dir)"
    local coverage_dir="$(_get_coverage_dir)"

    _copy_to "${source_dir}"

    for unicode_enabled in false ; do
        for xml_context in 0 1024 ; do
            local build_dir="$(_get_build_dir)"

            echo "[${build_dir}]"
            _copy_to "${build_dir}"
            _run "${source_dir}" "${build_dir}"

            build_dirs+=( "${build_dir}" )
        done
    done

    echo
    echo 'Merging coverage files...'
    _merge_coverage_info "${coverage_dir}" "${build_dirs[@]}"

    echo 'Rendering HTML report...'
    _render_html_report "${coverage_dir}"
    echo "--> ${coverage_dir}/index.html"

    echo
    _show_summary "${coverage_dir}"
}


_main