#!/bin/bash

# Test Suite for Recycle Bin System
# Autores: Maria Moreira Mané (125102), Claudino José Martins (127368)

SCRIPT="./recycle_bin.sh"
TEST_DIR="./test_data"
PASS=0
FAIL=0
TOTAL_TESTS=20

# Cores para output
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

setup() {
    echo "Setting up test environment..."
    mkdir -p "$TEST_DIR"
    rm -rf ~/.recycle_bin
    rm -f ~/.recycle_bin/.lock 
}

teardown() {
    echo "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    rm -rf ~/.recycle_bin 
}

assert_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $1"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC}: $1"
        ((FAIL++))
    fi
}

assert_fail() {
    if [ $? -ne 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $1"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC}: $1"
        ((FAIL++))
    fi
}

file_exists() {
    if [ -e "$1" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        ((FAIL++))
    fi
}

file_not_exists() {
    if [ ! -e "$1" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        ((FAIL++))
    fi
}

# ============================================================================
# CASOS DE TESTE - 20 TESTES NO TOTAL
# ============================================================================

test_01_initialization() {
    echo "=== Test 1/20: Initialization ==="
    $SCRIPT list > /dev/null 2>&1
    assert_success "Script executes without errors"
    [ -d ~/.recycle_bin ] && assert_success "Recycle bin directory created"
    [ -f ~/.recycle_bin/metadata.db ] && assert_success "Metadata file created"
    [ -d ~/.recycle_bin/files ] && assert_success "Files directory created"
    [ -f ~/.recycle_bin/config ] && assert_success "Config file created"
    echo ""
}

test_02_delete_single_file() {
    echo "=== Test 2/20: Delete Single File ==="
    echo "test content" > "$TEST_DIR/test_file.txt"
    $SCRIPT delete "$TEST_DIR/test_file.txt"
    assert_success "Delete existing file"
    file_not_exists "$TEST_DIR/test_file.txt" "File removed from original location"
    
    $SCRIPT list | grep -q "test_file.txt" && assert_success "File appears in recycle bin list"
    echo ""
}

test_03_delete_multiple_files() {
    echo "=== Test 3/20: Delete Multiple Files ==="
    echo "file1" > "$TEST_DIR/multi1.txt"
    echo "file2" > "$TEST_DIR/multi2.txt"
    echo "file3" > "$TEST_DIR/multi3.txt"
    
    $SCRIPT delete "$TEST_DIR/multi1.txt" "$TEST_DIR/multi2.txt" "$TEST_DIR/multi3.txt"
    assert_success "Delete multiple files in one command"
    
    file_not_exists "$TEST_DIR/multi1.txt" "First file removed"
    file_not_exists "$TEST_DIR/multi2.txt" "Second file removed"
    file_not_exists "$TEST_DIR/multi3.txt" "Third file removed"
    echo ""
}

test_04_delete_directory() {
    echo "=== Test 4/20: Delete Directory ==="
    mkdir -p "$TEST_DIR/test_dir"
    echo "content" > "$TEST_DIR/test_dir/file1.txt"
    echo "content" > "$TEST_DIR/test_dir/file2.txt"
    
    $SCRIPT delete "$TEST_DIR/test_dir"
    assert_success "Delete directory with contents"
    file_not_exists "$TEST_DIR/test_dir" "Directory removed from original location"
    echo ""
}

test_05_delete_nonexistent_file() {
    echo "=== Test 5/20: Delete Non-Existent File ==="
    $SCRIPT delete "$TEST_DIR/nonexistent.txt" 2>/dev/null
    assert_fail "Should fail on non-existent file"
    echo ""
}

test_06_list_functionality() {
    echo "=== Test 6/20: List Functionality ==="
    $SCRIPT list > /dev/null
    assert_success "List command works"
    $SCRIPT list --detailed > /dev/null
    assert_success "Detailed list works"
    echo ""
}

test_07_list_empty_bin() {
    echo "=== Test 7/20: List Empty Bin ==="
    $SCRIPT empty --force > /dev/null 2>&1
    $SCRIPT list | grep -q "empty" && assert_success "List shows empty bin message"
    echo ""
}

test_08_restore_functionality() {
    echo "=== Test 8/20: Restore Functionality ==="
    echo "restore test content" > "$TEST_DIR/restore_me.txt"
    $SCRIPT delete "$TEST_DIR/restore_me.txt"
    
    local file_info=$($SCRIPT list | grep "restore_me")
    if [ -n "$file_info" ]; then
        local file_id=$(echo "$file_info" | awk '{print $1}' | sed 's/\.\.\.$//')
        
        if [ -n "$file_id" ]; then
            echo "n" | $SCRIPT restore "$file_id" > /dev/null 2>&1
            assert_success "Restore file by ID (user cancelled)"
            
            $SCRIPT restore "$file_id" <<< "y" > /dev/null 2>&1
            assert_success "Restore file by ID"
            file_exists "$TEST_DIR/restore_me.txt" "File restored to original location"
        fi
    fi
    echo ""
}

test_09_restore_nonexistent_id() {
    echo "=== Test 9/20: Restore Non-Existent ID ==="
    $SCRIPT restore "nonexistent_id_123" 2>/dev/null
    assert_fail "Should fail on non-existent ID"
    echo ""
}

test_10_search_functionality() {
    echo "=== Test 10/20: Search Functionality ==="
    echo "search test" > "$TEST_DIR/search_test.txt"
    $SCRIPT delete "$TEST_DIR/search_test.txt"
    
    $SCRIPT search "search_test" > /dev/null
    assert_success "Search by filename works"
    
    $SCRIPT search "*.txt" > /dev/null
    assert_success "Search with wildcard works"
    
    $SCRIPT search "NONEXISTENT_PATTERN" > /dev/null
    assert_success "Search for non-existent pattern handles gracefully"
    echo ""
}

test_11_empty_functionality() {
    echo "=== Test 11/20: Empty Functionality ==="
    echo "temp1" > "$TEST_DIR/temp1.txt"
    echo "temp2" > "$TEST_DIR/temp2.txt"
    $SCRIPT delete "$TEST_DIR/temp1.txt" "$TEST_DIR/temp2.txt" > /dev/null
    
    $SCRIPT empty --force > /dev/null
    assert_success "Empty with force flag"
    
    $SCRIPT list | grep -q "empty" && assert_success "Bin is empty after emptying"
    echo ""
}

test_12_empty_specific_id() {
    echo "=== Test 12/20: Empty Specific ID ==="
    echo "specific file" > "$TEST_DIR/specific.txt"
    $SCRIPT delete "$TEST_DIR/specific.txt" > /dev/null
    
    local file_info=$($SCRIPT list | grep "specific")
    if [ -n "$file_info" ]; then
        local file_id=$(echo "$file_info" | awk '{print $1}' | sed 's/\.\.\.$//')
        
        if [ -n "$file_id" ]; then
            $SCRIPT empty "$file_id" --force > /dev/null 2>&1
            assert_success "Empty specific file by ID"
        fi
    fi
    echo ""
}

test_13_stats_functionality() {
    echo "=== Test 13/20: Statistics Functionality ==="
    echo "stats1" > "$TEST_DIR/stats1.txt"
    echo "stats2" > "$TEST_DIR/stats2.txt"
    $SCRIPT delete "$TEST_DIR/stats1.txt" "$TEST_DIR/stats2.txt" > /dev/null
    
    $SCRIPT stats > /dev/null
    assert_success "Stats command works"
    echo ""
}

test_14_preview_functionality() {
    echo "=== Test 14/20: Preview Functionality ==="
    echo "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11" > "$TEST_DIR/preview_test.txt"
    $SCRIPT delete "$TEST_DIR/preview_test.txt" > /dev/null
    
    local file_info=$($SCRIPT list | grep "preview_test")
    if [ -n "$file_info" ]; then
        local file_id=$(echo "$file_info" | awk '{print $1}' | sed 's/\.\.\.$//')
        
        if [ -n "$file_id" ]; then
            $SCRIPT preview "$file_id" > /dev/null 2>&1
            assert_success "Preview command works"
        fi
    fi
    echo ""
}

test_15_help_functionality() {
    echo "=== Test 15/20: Help Functionality ==="
    $SCRIPT help > /dev/null
    assert_success "Help command works"
    
    $SCRIPT --help > /dev/null
    assert_success "--help flag works"
    
    $SCRIPT -h > /dev/null
    assert_success "-h flag works"
    echo ""
}

test_16_files_with_spaces() {
    echo "=== Test 16/20: Files with Spaces ==="
    echo "content" > "$TEST_DIR/file with spaces.txt"
    $SCRIPT delete "$TEST_DIR/file with spaces.txt"
    assert_success "Delete file with spaces in name"
    file_not_exists "$TEST_DIR/file with spaces.txt" "File with spaces removed"
    echo ""
}

test_17_quota_management() {
    echo "=== Test 17/20: Quota Management ==="
    echo "quota test" > "$TEST_DIR/quota_test.txt"
    $SCRIPT delete "$TEST_DIR/quota_test.txt" 2>&1 | grep -q "QUOTA" && assert_success "Quota check is active"
    echo ""
}

test_18_auto_cleanup() {
    echo "=== Test 18/20: Auto-Cleanup ==="
    $SCRIPT cleanup > /dev/null 2>&1
    assert_success "Auto-cleanup command works"
    echo ""
}

test_19_security_validation() {
    echo "=== Test 19/20: Security Validation ==="
    $SCRIPT delete ~/.recycle_bin 2>/dev/null
    assert_fail "Should prevent deleting recycle bin itself"
    echo ""
}

test_20_concurrent_operations() {
    echo "=== Test 20/20: Concurrent Operations Protection ==="
    $SCRIPT list > /dev/null &
    $SCRIPT list > /dev/null &
    wait
    assert_success "Concurrent operations handled gracefully"
    echo ""
}

# ============================================================================
# EXECUÇÃO DOS TESTES
# ============================================================================

echo "========================================="
echo "    Recycle Bin System Test Suite"
echo "    Total Tests: $TOTAL_TESTS"
echo "========================================="
echo ""

setup

# Executar todos os 20 testes
test_01_initialization
test_02_delete_single_file
test_03_delete_multiple_files
test_04_delete_directory
test_05_delete_nonexistent_file
test_06_list_functionality
test_07_list_empty_bin
test_08_restore_functionality
test_09_restore_nonexistent_id
test_10_search_functionality
test_11_empty_functionality
test_12_empty_specific_id
test_13_stats_functionality
test_14_preview_functionality
test_15_help_functionality
test_16_files_with_spaces
test_17_quota_management
test_18_auto_cleanup
test_19_security_validation
test_20_concurrent_operations

teardown

echo "========================================="
echo "FINAL TEST RESULTS:"
echo "  $PASS tests passed"
echo "  $FAIL tests failed" 
echo "  Total: $((PASS + FAIL)) tests executed"
if [ $((PASS + FAIL)) -ne 0 ]; then
    echo "  Success rate: $((PASS * 100 / (PASS + FAIL)))%"
else
    echo "  Success rate: N/A"
fi
echo "========================================="

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN} ALL TESTS PASSED! Your recycle bin system is working perfectly!${NC}"
    exit 0
else
    echo -e "${YELLOW}  Some tests failed. Please check the implementation.${NC}"
    exit 1
fi