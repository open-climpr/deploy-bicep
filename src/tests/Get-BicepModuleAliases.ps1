BeforeAll {
    Import-Module $PSScriptRoot/../DeployBicepHelpers.psm1 -Force

    function New-FileStructure {
        param (
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [hashtable] $Structure
        )

        if (!(Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }

        foreach ($key in $Structure.Keys) {
            $itemPath = Join-Path -Path $Path -ChildPath $key
            if ($Structure[$key] -is [hashtable]) {
                New-FileStructure -Path $itemPath -Structure $Structure[$key]
            }
            else {
                Set-Content -Path $itemPath -Value $Structure[$key] -Force
            }
        }
    }
}

Describe "Get-BicepModuleAliases" {
    BeforeEach {
        $script:testRoot = Join-Path $TestDrive 'mock'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
    }

    Context "Built-in defaults" {
        It "Should return built-in defaults when no bicepconfig.json exists" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep' = ""
            }

            $result = Get-BicepModuleAliases -Path "$testRoot/main.bicep"

            $result | Should -BeOfType Hashtable
            $result.br.public.registry | Should -BeExactly "mcr.microsoft.com"
            $result.br.public.modulePath | Should -BeExactly "bicep"
        }

        It "Should return built-in defaults when called with a directory path and no bicepconfig.json exists" {
            $result = Get-BicepModuleAliases -Path $testRoot

            $result.br.public.registry | Should -BeExactly "mcr.microsoft.com"
        }
    }

    Context "Config file discovery" {
        It "Should find bicepconfig.json in the same directory as the file" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'       = ""
                'bicepconfig.json' = @{ moduleAliases = @{ br = @{ custom = @{ registry = "custom.azurecr.io"; modulePath = "m" } } } } | ConvertTo-Json -Depth 5
            }

            $result = Get-BicepModuleAliases -Path "$testRoot/main.bicep"

            $result.br.custom.registry | Should -BeExactly "custom.azurecr.io"
        }

        It "Should find bicepconfig.json in a parent directory" {
            New-FileStructure -Path $testRoot -Structure @{
                'bicepconfig.json' = @{ moduleAliases = @{ br = @{ custom = @{ registry = "custom.azurecr.io"; modulePath = "m" } } } } | ConvertTo-Json -Depth 5
                'subdir'           = @{
                    'main.bicep' = ""
                }
            }

            $result = Get-BicepModuleAliases -Path "$testRoot/subdir/main.bicep"

            $result.br.custom.registry | Should -BeExactly "custom.azurecr.io"
        }

        It "Should find the nearest bicepconfig.json when multiple exist in parent directories" {
            New-FileStructure -Path $testRoot -Structure @{
                'bicepconfig.json' = @{ moduleAliases = @{ br = @{ custom = @{ registry = "parent.azurecr.io"; modulePath = "m" } } } } | ConvertTo-Json -Depth 5
                'subdir'           = @{
                    'bicepconfig.json' = @{ moduleAliases = @{ br = @{ custom = @{ registry = "child.azurecr.io"; modulePath = "m" } } } } | ConvertTo-Json -Depth 5
                    'main.bicep'       = ""
                }
            }

            $result = Get-BicepModuleAliases -Path "$testRoot/subdir/main.bicep"

            $result.br.custom.registry | Should -BeExactly "child.azurecr.io"
        }

        It "Should accept a directory path as input" {
            New-FileStructure -Path $testRoot -Structure @{
                'bicepconfig.json' = @{ moduleAliases = @{ br = @{ custom = @{ registry = "custom.azurecr.io"; modulePath = "m" } } } } | ConvertTo-Json -Depth 5
                'subdir'           = @{}
            }

            $result = Get-BicepModuleAliases -Path "$testRoot/subdir"

            $result.br.custom.registry | Should -BeExactly "custom.azurecr.io"
        }
    }

    Context "Alias resolution" {
        It "Should merge user-defined aliases with built-in defaults" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'       = ""
                'bicepconfig.json' = @{
                    moduleAliases = @{
                        br = @{
                            myRegistry = @{
                                registry   = "myregistry.azurecr.io"
                                modulePath = "modules"
                            }
                        }
                    }
                } | ConvertTo-Json -Depth 5
            }

            $result = Get-BicepModuleAliases -Path "$testRoot/main.bicep"

            $result.br.public.registry | Should -BeExactly "mcr.microsoft.com"
            $result.br.myRegistry.registry | Should -BeExactly "myregistry.azurecr.io"
        }

        It "Should allow user config to override the built-in public alias" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'       = ""
                'bicepconfig.json' = @{
                    moduleAliases = @{
                        br = @{
                            public = @{
                                registry   = "custom.azurecr.io"
                                modulePath = "custom"
                            }
                        }
                    }
                } | ConvertTo-Json -Depth 5
            }

            $result = Get-BicepModuleAliases -Path "$testRoot/main.bicep"

            $result.br.public.registry | Should -BeExactly "custom.azurecr.io"
        }
    }

    Context "Termination" {
        It "Should not loop forever when no bicepconfig.json exists anywhere in the tree" {
            New-FileStructure -Path $testRoot -Structure @{
                'a' = @{
                    'b' = @{
                        'c' = @{
                            'main.bicep' = ""
                        }
                    }
                }
            }

            { Get-BicepModuleAliases -Path "$testRoot/a/b/c/main.bicep" } | Should -Not -Throw
        }
    }
}
