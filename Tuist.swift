import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(enableCaching: false),
        cacheOptions: .options(storages: [.local])
    )
)
